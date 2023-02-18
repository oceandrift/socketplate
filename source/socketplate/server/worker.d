/++
    Listener and worker implementation
 +/
module socketplate.server.worker;

import core.atomic : atomicLoad, atomicStore;
import socketplate.connection;
import socketplate.log;
import std.conv : to;
import std.string : format;
import std.socket : Address, socket_t, Socket, SocketShutdown;

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
    }

    public this(Socket socket, Address address, ConnectionHandler callback) pure nothrow @nogc
    {
        _socket = socket;
        _address = address;
        _callback = callback;

        _state = State.initial;
    }

    public bool isClosed() pure nothrow @nogc
    {
        return (_state == State.closed);
    }

    public void bind()
    in (_state == State.initial)
    {
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

    public void accept(size_t workerID)
    in (_state == State.listening)
    {
        logTrace(format!"Accepting incoming connections (#%X @%02d)"(_socket.handle, workerID));
        Socket accepted = _socket.accept();

        socket_t acceptedID = accepted.handle;

        logTrace(format!"Incoming connection accepted (#%X @%02d)"(acceptedID, workerID));
        try
            _callback(SocketConnection(accepted));
        catch (Exception ex)
            logError(
                format!"Unhandled Exception in connection handler (#%X): %s"(acceptedID, ex.msg)
            );

        logTrace(format!"Connection handled (#%X)"(acceptedID));

        if (accepted.isAlive)
        {
            logTrace(format!"Closing still-alive connection (#%X)"(acceptedID));
            accepted.close();
        }
    }

    private void shutdownClose()
    in (_state != State.closed)
    {
        logTrace(format!"Shutting down socket (#%X)"(_socket.handle));
        _socket.shutdown(SocketShutdown.BOTH);

        logTrace(format!"Closing socket (#%X)"(_socket.handle));
        _socket.close();

        _state = State.closed;
    }

    public void ensureShutdownClosed()
    {
        if (_state == State.closed)
            return;

        shutdownClose();
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
    }

    public this(SocketListener listener, size_t id = 0)
    {
        _listener = listener;
        _id = id;
    }

    public void run()
    {
        _active.atomicStore = true;
        while (atomicLoad(_active))
            _listener.accept(_id);
    }

    public void shutdown() shared
    {
        _active.atomicStore = false;
    }
}
