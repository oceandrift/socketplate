/++
    Worker pool implementation
 +/
module socketplate.server.pool;

import core.thread;
import socketplate.connection;
import socketplate.log;
import socketplate.server.tunables;
import socketplate.server.worker;
import std.format;

@safe:

/++
    Configurable worker-spawning mechanism
 +/
final class WorkerPool {
    private {
        SocketServerTunables _tunables;
        const bool _spawnDynamically;
        const int _configuredWorkers;

        bool _noShutdownSignalReceived = true;
        Thread[] _threads;
        Worker[] _workers;
        PoolListenerMeta[] _metas;
    }

    ///
    public this(SocketServerTunables tunables, SocketListener[] listeners) {
        _tunables = tunables;
        _spawnDynamically = (_tunables.workerSpawningStrategy == SpawningStrategy.dynamic);

        if (_spawnDynamically) {
            if (_tunables.workers > _tunables.workersMax) {
                enum errorFmt = "The requested number of workers (%s) is greater than the configured maximum (%s).";
                logError(format!errorFmt(_tunables.workers, _tunables.workersMax));

                // fix workers count
                _configuredWorkers = _tunables.workersMax;
            } else {
                if (_tunables.workers == _tunables.workersMax) {
                    enum warningFmt = "The requested number of workers (%s) matches the configured maximum (%s).";
                    logWarning(format!warningFmt(_tunables.workers, _tunables.workersMax));
                }

                _configuredWorkers = _tunables.workers;
            }
        } else {
            _configuredWorkers = _tunables.workers;
        }

        _metas.reserve(listeners.length);
        foreach (listener; listeners) {
            auto poolComm = new PoolCommunicator();
            _metas ~= PoolListenerMeta(
                listener,
                poolComm,
                0,
            );
        }

        size_t nWorkers = (_metas.length * _configuredWorkers);
        _workers.reserve(nWorkers);
    }

    public {
        ///
        int run() {
            logTrace("Starting SocketServer in Threading mode");

            scope (exit) {
                foreach (worker; _workers) {
                    worker.shutdown();
                }
            }

            // spawn threads
            foreach (ref meta; _metas) {
                meta.listener.listen(_tunables.backlog);
                this.spawnWorkerThreads(meta, _tunables.workers);
            }

            // setup signal handlers (if requested)
            if (_tunables.setupSignalHandlers) {
                import socketplate.signal;

                setupSignalHandlers(delegate(int signal) @safe nothrow @nogc {
                    _noShutdownSignalReceived = false;

                    // signal threads
                    forwardSignal(signal, _threads);
                });
            }

            // start worker threads
            foreach (Thread thread; _threads) {
                function(Thread thread) @trusted { thread.start(); }(thread);
            }

            // dynamic worker spawning (if applicable)
            if (_spawnDynamically) {
                this.waitForWorkersToStart();
                this.dynamicSpawnLoop();
            }

            bool workerError = false;

            // wait for workers to exit
            foreach (thread; _threads) {
                function(Thread thread, ref workerError) @trusted {
                    try {
                        thread.join(true);
                    } catch (Exception) {
                        workerError = true;
                    }
                }(thread, workerError);
            }

            // determine exit-code
            return (workerError) ? 1 : 0;
        }
    }

    private {
        // Waits until all workers have started
        void waitForWorkersToStart() {
            foreach (ref meta; _metas) {
                workersOfListenerStarted: while (true) {
                    if (!_noShutdownSignalReceived) {
                        return;
                    }

                    if (meta.allStarted()) {
                        break workersOfListenerStarted;
                    }

                    logTrace(format!"%s of %s threads started"(meta.comm.statusStarted, meta.workers));

                    // wait
                    (() @trusted => Thread.sleep(1.seconds))();
                }
            }
        }

        // Scans threads for exited ones
        bool scanThreads() {
            foreach (thread; _threads) {
                immutable bool isRunning = (() @trusted => thread.isRunning)();
                if (isRunning) {
                    return true;
                }
            }

            logWarning("No more threads running.");
            return false;
        }

        void dynamicSpawnLoop()
        in (_spawnDynamically) {
            while (_noShutdownSignalReceived && this.scanThreads()) {
                size_t hitMax = 0;
                foreach (idx, ref meta; _metas) {
                    if (meta.busy) {
                        if (meta.workers >= _tunables.workersMax) {
                            enum msg = "All workers of listener #%s are busy."
                                ~ " Hit maximum of %s workers per listener.";
                            logTrace(format!msg(idx, _tunables.workersMax));
                            ++hitMax;
                            continue;
                        }

                        logTrace(format!"All workers of listener #%s are busy. Spawning a further worker."(idx));
                        Thread thread = this.spawnWorkerThread(meta);
                        ((Thread thread) @trusted => thread.start())(thread);
                    }
                }

                if (hitMax == _metas.length) {
                    // leave monitoring loop
                    break;
                }

                (() @trusted => Thread.sleep(1.msecs))();
            }
        }

        void spawnWorkerThreads(
            ref PoolListenerMeta meta,
            int n,
        ) {
            foreach (idx; 0 .. n) {
                this.spawnWorkerThread(meta);
            }
        }

        Thread spawnWorkerThread(
            ref PoolListenerMeta meta,
        ) {
            immutable id = _threads.length;
            Thread spawned = this.spawnWorkerThread(meta.comm, id, meta.listener);
            _threads ~= spawned;
            ++meta.workers;

            return spawned;
        }

        Thread spawnWorkerThread(
            PoolCommunicator poolComm,
            size_t id,
            SocketListener listener,
        ) {
            auto worker = new Worker(poolComm, listener, id, _tunables.setupSignalHandlers);
            _workers ~= worker;
            return new Thread(&worker.run);
        }
    }
}

struct PoolListenerMeta {
    SocketListener listener;
    PoolCommunicator comm;
    int workers = 0;

@safe:

    bool busy() nothrow @nogc const {
        return (comm.status >= workers);
    }

    bool allStarted() nothrow @nogc const {
        return (comm.statusStarted >= workers);
    }
}
