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

        bool _started = false;
        bool _noShutdownSignalReceived = true;
        Worker[] _workers;
        PoolListenerMeta[] _metas;
    }

    ///
    public this(SocketServerTunables tunables, SocketListener[] listeners) {
        // store server tunables
        _tunables = tunables;

        // setup worker
        bool spawnDynamically = false;
        int nWorkers = 0;

        foreach (listener; listeners) {
            int configuredWorkers = listener.tunables.workers;

            if (listener.isDynamicallySpawned) {
                spawnDynamically = true;

                if (configuredWorkers > listener.tunables.workersMax) {
                    enum errorFmt = "The requested number of workers (%s) is greater than the configured maximum (%s).";
                    logError(format!errorFmt(listener.tunables.workers, listener.tunables.workersMax));

                    // fix workers count
                    configuredWorkers = listener.tunables.workersMax;
                } else if (listener.tunables.workers == listener.tunables.workersMax) {
                    enum warningFmt = "The requested number of workers (%s) matches the configured maximum (%s).";
                    logWarning(format!warningFmt(listener.tunables.workers, listener.tunables.workersMax));
                }
            }

            nWorkers += configuredWorkers;
        }

        _spawnDynamically = spawnDynamically;

        _metas.reserve(listeners.length);
        foreach (listener; listeners) {
            auto poolComm = new PoolCommunicator();
            auto id = _metas.length;
            _metas ~= PoolListenerMeta(
                id,
                listener,
                poolComm,
                [],
            );
        }

        _workers.reserve(nWorkers);
    }

    public {
        ///
        int run()
        in (!_started, "Pool has already been started.") {
            _started = true;
            logTrace("Starting SocketServer in Threading mode");

            scope (exit) {
                foreach (worker; _workers) {
                    worker.shutdown();
                }
            }

            // spawn threads
            foreach (ref meta; _metas) {
                meta.listener.listen();
                this.spawnWorkerThreads(meta);
            }

            // setup signal handlers (if requested)
            if (_tunables.setupSignalHandlers) {
                import socketplate.signal;

                setupSignalHandlers(delegate(int signal) @safe nothrow @nogc {
                    _noShutdownSignalReceived = false;

                    // signal threads
                    foreach (ref meta; _metas) {
                        forwardSignal(signal, meta.threads);
                    }
                });
            }

            // start worker threads
            foreach (ref meta; _metas) {
                foreach (Thread thread; meta.threads) {
                    function(Thread thread) @trusted { thread.start(); }(thread);
                }
            }

            // dynamic worker spawning (if applicable)
            if (_spawnDynamically) {
                this.waitForWorkersToStart();
                this.dynamicSpawningLoop();
            }

            bool workerError = false;

            // wait for workers to exit
            foreach (ref meta; _metas) {
                foreach (thread; meta.threads) {
                    function(Thread thread, ref workerError) @trusted {
                        try {
                            thread.join(true);
                        } catch (Exception) {
                            workerError = true;
                        }
                    }(thread, workerError);
                }
            }

            // determine exit-code
            return (workerError) ? 1 : 0;
        }
    }

    private {
        // Waits until all workers have started
        void waitForWorkersToStart() {
            foreach (idx, ref meta; _metas) {
                // skip non-dynamic workers
                if (meta.isDynamicallySpawned) {
                    continue;
                }

                while (!meta.allStarted()) {
                    if (!_noShutdownSignalReceived) {
                        return;
                    }

                    enum msg = "Listener ~%s: %s of %s workers started. Waiting.";
                    logTrace(format!msg(idx, meta.comm.statusStarted, meta.workerCount));

                    // wait
                    (() @trusted => Thread.sleep(1.seconds))();
                }
            }
        }

        // Monitors dynamic listeners and spawns additional workers as needed.
        void dynamicSpawningLoop()
        in (_spawnDynamically) {
            import std.algorithm : remove;

            PoolListenerMeta*[] monitored;
            foreach (ref meta; _metas) {
                if (meta.isDynamicallySpawned) {
                    monitored ~= &meta;
                }
            }

            while (_noShutdownSignalReceived) {
                foreach (idx, PoolListenerMeta* meta; monitored) {
                    if (!scanThreads(*meta)) {
                        monitored = monitored.remove(idx);
                        break; // break foreach-loop after removal; `idx` is invalid.
                    }

                    if (meta.busy) {
                        if (meta.workerCount >= meta.listener.tunables.workersMax) {
                            enum msg = "All workers of listener ~%s are busy."
                                ~ " Hit maximum of %s workers per listener.";
                            logTrace(format!msg(meta.id, meta.listener.tunables.workersMax));

                            monitored = monitored.remove(idx);
                            break; // break foreach-loop after removal; `idx` is invalid.
                        }
                        enum msgSpawnAdditional = "All workers of listener ~%s are busy."
                            ~ " Spawning an additional worker.";
                        logTrace(format!msgSpawnAdditional(meta.id));

                        Thread thread = this.spawnWorkerThread(*meta);
                        ((Thread thread) @trusted => thread.start())(thread);
                    }
                }

                if (monitored.length == 0) {
                    // leave monitoring loop
                    logTrace("Dynamic maximum of workers has been spawned.");
                    break;
                }

                (() @trusted => Thread.sleep(1.msecs))();
            }

            logTrace("Leaving dynamic-spawning loop.");
        }

        // Spawns as many workers as configured at listener-level.
        void spawnWorkerThreads(
            ref PoolListenerMeta meta,
        ) {
            foreach (idx; 0 .. meta.listener.tunables.workers) {
                this.spawnWorkerThread(meta);
            }
        }

        Thread spawnWorkerThread(
            ref PoolListenerMeta meta,
        ) {
            immutable threadID = meta.threads.length;
            immutable listenerID = meta.id;

            Thread spawned = this.spawnWorkerThread(meta.comm, listenerID, threadID, meta.listener);
            meta.threads ~= spawned;

            return spawned;
        }

        Thread spawnWorkerThread(
            PoolCommunicator poolComm,
            size_t listenerID,
            size_t threadID,
            SocketListener listener,
        ) {
            string id = format!"%d-%02d"(listenerID, threadID);

            auto worker = new Worker(poolComm, listener, id, _tunables.setupSignalHandlers);
            _workers ~= worker;
            return new Thread(&worker.run);
        }
    }
}

private:

struct PoolListenerMeta {
    size_t id;
    SocketListener listener;
    PoolCommunicator comm;
    Thread[] threads;

@safe:

    size_t workerCount() const pure nothrow @nogc {
        return threads.length;
    }

    bool busy() nothrow @nogc const {
        return (comm.status >= workerCount);
    }

    bool allStarted() nothrow @nogc const {
        return (comm.statusStarted >= workerCount);
    }
}

bool isDynamicallySpawned(const ref SocketListener listener) pure nothrow @nogc {
    return (listener.tunables.workerSpawningStrategy == SpawningStrategy.dynamic);
}

bool isDynamicallySpawned(const ref PoolListenerMeta meta) pure nothrow @nogc {
    return isDynamicallySpawned(meta.listener);
}

// Scans threads for non-exited ones.
bool scanThreads(ref PoolListenerMeta meta) {
    foreach (thread; meta.threads) {
        immutable bool isRunning = (() @trusted => thread.isRunning)();
        if (isRunning) {
            return true;
        }
    }

    logWarning("No more threads running.");
    return false;
}
