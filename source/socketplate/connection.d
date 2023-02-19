/++
    Socket connection
 +/
module socketplate.connection;

import socketplate.log;
import std.format;
import std.socket;

///
alias ConnectionHandler = void delegate(SocketConnection) @safe;

///
struct SocketConnection
{
@safe:

    private
    {
        Socket _socket;
    }

    enum error = Socket.ERROR;

    @disable this();
    @disable this(this);

    this(Socket socket) pure nothrow @nogc
    {
        _socket = socket;
    }

    /++
        Closes the connection
     +/
    void close() nothrow @nogc
    {
        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();
        _socket = null;
    }

    /++
        Reads received data into the provided buffer

        Returns:
            Number of bytes received
            (`0` indicated that the connection got closed before receiving any bytes)

            or [SocketConnection.error] = on failure
     +/
    ptrdiff_t receive(scope void[] buffer)
    {
        logTrace(format!"Receiving bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.receive(buffer);

        logTrace(format!"Received bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }

    /++
        Reads received data into the provided buffer

        Returns:
            Slice of buffer containing the received data.

            Length of `0` indicates that the connection has been closed

        Throws:
            Exception on failure
     +/
    T[] receiveSlice(T)(return scope T[] buffer)
            if (is(T == void) || is(T == ubyte) || is(T == char))
    {
        ptrdiff_t bytesReceived = this.receive(buffer);

        if (bytesReceived < 0)
            throw new Exception("An error occured while receiving data");

        return buffer[0 .. bytesReceived];
    }

    /++
        Reads received data into the provided buffer

        Returns:
            Slice of buffer containing the received data.

            Length of `0` indicates that the connection has been closed

        Throws:
            Exception on failure
     +/
    T[] receiveAll(bool force = true, T)(return scope T[] buffer)
            if (is(T == void) || is(T == ubyte) || is(T == char))
    {
        static if (!force)
            ptrdiff_t bytesReceivedTotal = 0;

        ptrdiff_t bytesReceived = 0;
        T[] bufferLeft = buffer;

        while (bufferLeft.length > 0)
        {
            bytesReceived = this.receive(bufferLeft);

            if (bytesReceived < 0)
                throw new Exception("An error occured while receiving data");
            if (bytesReceived == 0)
            {
                static if (!force)
                    return buffer[0 .. bytesReceivedTotal];
                else
                    throw new Exception(
                        "Connection was closed before all of the provided buffer could have been filled"
                    );
            }

            bufferLeft = bufferLeft[bytesReceived .. $];
            static if (!force)
                bytesReceivedTotal += bytesReceived;
        }

        return buffer;
    }

    /++
        Sends data on the connection

        Returns:
            number of bytes sent

            or [SocketConnection.error] on failure
     +/
    ptrdiff_t send(scope const(void)[] buffer)
    {
        logTrace(format!"Sending bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.send(buffer);

        logTrace(format!"Sent bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }

    /++
        Sends all data from the passed slice on the connection

        Throws:
            Exception on failure
     +/
    void sendAll(scope const(void)[] buffer)
    {
        ptrdiff_t bytesSent = 0;
        const(void)[] bufferLeft = buffer;

        while (bufferLeft.length > 0)
        {
            bytesSent = this.send(bufferLeft);

            if (bytesSent < 0)
                throw new Exception("An error occured while sending data");

            bufferLeft = bufferLeft[bytesSent .. $];
        }
    }
}
