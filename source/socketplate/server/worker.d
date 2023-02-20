/++
    Listener and worker implementation
 +/
module socketplate.server.worker;

import core.atomic : atomicLoad, atomicStore;
import socketplate.connection;
import socketplate.log;
import std.conv : to;
import std.string : format;
import std.socket : Address, Socket, SocketShutdown;

@safe:

final class SocketListener
{
@safe:

    private enum State
    {
        initial,
        bound,
        listening,
        closed,
    }

    private
    {
        State _state;

        Socket _socket;
        Address _address;
        ConnectionHandler _callback;
        int _timeout;
        static Socket _accepted = null;
    }

    public this(Socket socket, Address address, ConnectionHandler callback, int timeout) pure nothrow @nogc
    {
        _socket = socket;
        _address = address;
        _callback = callback;
        _timeout = timeout;

        _state = State.initial;
    }

    public bool isClosed() pure nothrow @nogc
    {
        return (_state == State.closed);
    }

    public void bind(bool socketOptionREUSEADDR = true)
    in (_state == State.initial)
    {
        // unlink Unix Domain Socket file if applicable
        unlinkUnixDomainSocket(_address);

        // enable address reuse
        _socket.setReuseAddr = socketOptionREUSEADDR;

        logTrace(format!"Binding to %s (#%X)"(_address.toString, _socket.handle));
        _socket.bind(_address);
        _state = State.bound;
    }

    public void listen(int backlog)
    in (_state == State.bound)
    {
        logTrace(format!"Listening on %s (#%X)"(_address.toString, _socket.handle));
        _socket.listen(backlog);
        _state = State.listening;
    }

    private void accept(size_t workerID)
    in (_state == State.listening)
    {
        import std.socket : socket_t;

        logTrace(format!"Accepting incoming connections (#%X @%02d)"(_socket.handle, workerID));
        _accepted = _socket.accept();

        socket_t acceptedID = _accepted.handle;

        logTrace(format!"Incoming connection accepted (#%X @%02d)"(acceptedID, workerID));
        try
            _callback(makeSocketConnection(_accepted, _timeout));
        catch (Exception ex)
            logError(
                format!"Unhandled Exception in connection handler (#%X): %s"(acceptedID, ex.msg)
            );

        logTrace(format!"Connection handled (#%X)"(acceptedID));

        if (_accepted.isAlive)
        {
            logTrace(format!"Closing still-alive connection (#%X)"(acceptedID));
            _accepted.close();
        }
    }

    private void shutdownClose(bool doLog = true)()
    in (_state != State.closed)
    {
        static if (doLog)
            logTrace(format!"Shutting down socket (#%X)"(_socket.handle));
        _socket.shutdown(SocketShutdown.BOTH);

        static if (doLog)
            logTrace(format!"Closing socket (#%X)"(_socket.handle));
        _socket.close();

        _state = State.closed;
    }

    private void ensureShutdownClosed()
    {
        if (_state == State.closed)
            return;

        shutdownClose!true();
    }

    private void ensureShutdownClosedNoLog() nothrow @nogc
    {
        if (_state == State.closed)
            return;

        shutdownClose!false();
    }

    private void shutdownAccepted() nothrow @nogc
    {
        if (_accepted is null)
            return;

        _accepted.shutdown(SocketShutdown.BOTH);
        _accepted.close();
    }
}

class Worker
{
@safe:

    private
    {
        shared(bool) _active = false;

        size_t _id;
        SocketListener _listener;
        bool _setupSignalHandlers;
    }

    public this(SocketListener listener, size_t id, bool setupSignalHandlers)
    {
        _listener = listener;
        _id = id;
        _setupSignalHandlers = setupSignalHandlers;
    }

    public void run()
    {
        import std.socket : SocketException;

        scope (exit)
            logTrace(format!"Worker @%02d says goodbye"(_id));

        if (_setupSignalHandlers)
            doSetupSignalHandlers();

        scope (exit)
        {
            logInfo(format!"Worker @%02d exiting"(_id));
            _listener.ensureShutdownClosed();
        }

        _active.atomicStore = true;
        while (atomicLoad(_active))
        {
            try
                _listener.accept(_id);
            catch (SocketException)
                break;
        }
    }

    public void shutdown() nothrow @nogc
    {
        _active.atomicStore = false;
    }

    private void doSetupSignalHandlers()
    {
        import socketplate.signal;

        setupSignalHandlers((int) @safe nothrow @nogc {
            this.shutdown();
            this._listener.ensureShutdownClosedNoLog();
            this._listener.shutdownAccepted();
        });
    }
}

private SocketConnection makeSocketConnection(Socket socket, int seconds)
{
    auto sc = SocketConnection(socket);
    sc.timeout!(Direction.receive)(seconds);
    return sc;
}

private void setReuseAddr(Socket socket, bool enable)
{
    import std.socket : SocketOption, SocketOptionLevel;

    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, enable);
}

private void unlinkUnixDomainSocket(Address addr)
{
    import std.socket : AddressFamily;

    version (Posix)
    {
        if (addr.addressFamily == AddressFamily.UNIX)
        {
            import core.sys.posix.unistd : unlink;
            import std.file : exists;
            import std.socket : UnixAddress;
            import std.string : toStringz;

            UnixAddress uaddr = cast(UnixAddress) addr;

            if (uaddr is null)
            {
                logError("Cannot determine path of Unix Domain Socket");
                return;
            }

            if (!uaddr.path.exists)
            {
                logTrace("Unix Domain Socket path does not exists; nothing to unlink");
                return;
            }

            logTrace(format!"Unlinking Unix Domain Socket file: %s"(uaddr.path));
            int r = () @trusted { return unlink(uaddr.path.toStringz); }();

            if (r != 0)
                logTrace(format!"Unlinking failed with status: %d"(r));
        }
    }
}
