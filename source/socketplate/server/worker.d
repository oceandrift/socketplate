/++
    Listener and worker implementation
 +/
module socketplate.server.worker;

import core.atomic : atomicLoad, atomicStore;
import socketplate.connection;
import socketplate.log;
import socketplate.server.tunables;
import std.conv : to;
import std.string : format;
import std.socket : Address, Socket, SocketShutdown;

@safe:

package(socketplate.server) final class PoolCommunicator {
    import core.atomic;

    private {
        shared(int) _startedWorkers = 0;
        shared(int) _occupiedWorkers = 0;
    }

@safe nothrow @nogc:

    void notifyStarted() {
        _startedWorkers.atomicOp!"+="(1);
    }

    void notifyDoing() {
        _occupiedWorkers.atomicOp!"+="(1);
    }

    void notifyDone() {
        _occupiedWorkers.atomicOp!"-="(1);
    }

    int statusStarted() const {
        return atomicLoad(_startedWorkers);
    }

    int status() const {
        return atomicLoad(_occupiedWorkers);
    }
}

final class SocketListener {
@safe:

    private enum State {
        initial,
        bound,
        listening,
        closed,
    }

    private {
        State _state;

        Socket _socket;
        Address _address;
        ConnectionHandler _callback;
        SocketListenerTunables _tunables;
        static Socket _accepted = null;
    }

    public this(Socket socket, Address address, ConnectionHandler callback, SocketListenerTunables tunables) pure nothrow @nogc {
        _socket = socket;
        _address = address;
        _callback = callback;
        _tunables = tunables;

        _state = State.initial;
    }

    ref const(SocketListenerTunables) tunables() const pure nothrow @nogc {
        return _tunables;
    }

    public bool isClosed() pure nothrow @nogc {
        return (_state == State.closed);
    }

    public void bind(bool socketOptionREUSEADDR = true)
    in (_state == State.initial) {
        // unlink Unix Domain Socket file if applicable
        unlinkUnixDomainSocket(_address);

        // enable address reuse
        _socket.setReuseAddr = socketOptionREUSEADDR;

        logTrace(format!"Binding to %s (#%X)"(_address.toString, _socket.handle));
        _socket.bind(_address);
        _state = State.bound;
    }

    public void listen()
    in (_state == State.bound) {
        logTrace(format!"Listening on %s (#%X)"(_address.toString, _socket.handle));
        _socket.listen(_tunables.backlog);
        _state = State.listening;
    }

    private void accept(size_t workerID, PoolCommunicator poolComm)
    in (_state == State.listening) {
        import std.socket : socket_t;

        logTrace(format!"Accepting incoming connections (#%X @%02d)"(_socket.handle, workerID));
        _accepted = _socket.accept();

        poolComm.notifyDoing();
        scope (exit) {
            poolComm.notifyDone();
        }

        socket_t acceptedID = _accepted.handle;

        logTrace(format!"Incoming connection accepted (#%X @%02d)"(acceptedID, workerID));
        try {
            _callback(makeSocketConnection(_accepted, _tunables.timeout));
        } catch (Exception ex) {
            logError(
                format!"Unhandled Exception in connection handler (#%X): %s"(acceptedID, ex.msg)
            );
        }

        logTrace(format!"Connection handled (#%X)"(acceptedID));

        if (_accepted.isAlive) {
            logTrace(format!"Closing still-alive connection (#%X)"(acceptedID));
            _accepted.close();
        }
    }

    private void shutdownClose(bool doLog = true)()
    in (_state != State.closed) {
        static if (doLog) {
            logTrace(format!"Shutting down socket (#%X)"(_socket.handle));
        }
        _socket.shutdown(SocketShutdown.BOTH);

        static if (doLog) {
            logTrace(format!"Closing socket (#%X)"(_socket.handle));
        }
        _socket.close();

        _state = State.closed;
    }

    private void ensureShutdownClosed() {
        if (_state == State.closed) {
            return;
        }

        shutdownClose!true();
    }

    private void ensureShutdownClosedNoLog() nothrow @nogc {
        if (_state == State.closed) {
            return;
        }

        shutdownClose!false();
    }

    private void shutdownAccepted() nothrow @nogc {
        if (_accepted is null) {
            return;
        }

        _accepted.shutdown(SocketShutdown.BOTH);
        _accepted.close();
    }
}

final class Worker {
@safe:

    private {
        shared(bool) _active = false;

        size_t _id;
        SocketListener _listener;
        PoolCommunicator _poolComm;
        bool _setupSignalHandlers;
    }

    public this(PoolCommunicator poolComm, SocketListener listener, size_t id, bool setupSignalHandlers) {
        _poolComm = poolComm;
        _listener = listener;
        _id = id;
        _setupSignalHandlers = setupSignalHandlers;
    }

    public void run() {
        import std.socket : SocketException;

        _poolComm.notifyStarted();

        scope (exit) {
            logTrace(format!"Worker @%02d says goodbye"(_id));
        }

        if (_setupSignalHandlers) {
            doSetupSignalHandlers();
        }

        scope (exit) {
            logInfo(format!"Worker @%02d exiting"(_id));
            _listener.ensureShutdownClosed();
        }

        _active.atomicStore = true;
        while (atomicLoad(_active)) {
            try {
                _listener.accept(_id, _poolComm);
            } catch (SocketException) {
                break;
            }
        }
    }

    public void shutdown() nothrow @nogc {
        _active.atomicStore = false;
    }

    private void doSetupSignalHandlers() {
        import socketplate.signal;

        setupSignalHandlers((int) @safe nothrow @nogc {
            this.shutdown();
            this._listener.ensureShutdownClosedNoLog();
            this._listener.shutdownAccepted();
        });
    }
}

private SocketConnection makeSocketConnection(Socket socket, int seconds) {
    auto sc = SocketConnection(socket);
    sc.timeout!(Direction.receive)(seconds);
    return sc;
}

private void setReuseAddr(Socket socket, bool enable) {
    import std.socket : SocketOption, SocketOptionLevel;

    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, enable);
}

private void unlinkUnixDomainSocket(Address addr) {
    import std.socket : AddressFamily;

    version (Posix) {
        if (addr.addressFamily == AddressFamily.UNIX) {
            import core.sys.posix.unistd : unlink;
            import std.file : exists;
            import std.socket : UnixAddress;
            import std.string : toStringz;

            UnixAddress uaddr = cast(UnixAddress) addr;

            if (uaddr is null) {
                logError("Cannot determine path of Unix Domain Socket");
                return;
            }

            if (!uaddr.path.exists) {
                logTrace("Unix Domain Socket path does not exists; nothing to unlink");
                return;
            }

            logTrace(format!"Unlinking Unix Domain Socket file: %s"(uaddr.path));
            int r = () @trusted { return unlink(uaddr.path.toStringz); }();

            if (r != 0) {
                logTrace(format!"Unlinking failed with status: %d"(r));
            }
        }
    }
}
