module socketplate.connection;

import socketplate.log;
import std.format;
import std.socket;

alias ConnectionHandler = void delegate(SocketConnection) @safe;

struct SocketConnection
{
@safe:

    private
    {
        Socket _socket;
    }

    enum error = Socket.ERROR;

    @disable this();

    this(Socket socket)
    {
        _socket = socket;
    }

    void close() nothrow @nogc
    {
        _socket.close();
    }

    ptrdiff_t receive(scope void[] buffer)
    {
        logTrace(format!"Receiving bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.receive(buffer);

        logTrace(format!"Received bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }

    ptrdiff_t send(scope void[] buffer)
    {
        logTrace(format!"Sending bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.send(buffer);

        logTrace(format!"Sent bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }
}
