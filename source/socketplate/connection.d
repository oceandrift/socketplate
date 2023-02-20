/++
    Socket connection
 +/
module socketplate.connection;

import socketplate.log;
import std.format;
import std.socket;

@safe:

///
alias ConnectionHandler = void delegate(SocketConnection) @safe;

///
enum socketERROR = Socket.ERROR;

///
struct SocketConnection
{
@safe:

    private
    {
        Socket _socket;
    }

    @disable private this();
    @disable private this(this);

    this(Socket socket) pure nothrow @nogc
    {
        _socket = socket;
    }

    /++
        Determines whether the socket is still alive
     +/
    bool isAlive() const
    {
        return _socket.isAlive;
    }

    /++
        Determines whether there is no more data to be received
     +/
    bool empty()
    {
        ubyte[1] tmp;
        immutable ptrdiff_t bytesReceived = _socket.receive(tmp, SocketFlags.PEEK);
        return ((bytesReceived == 0) || (bytesReceived == socketERROR));
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

            or [socketplate.connection.socketERROR|socketERROR] = on failure

        Throws:
            [SocketTimeoutException] on timeout
     +/
    ptrdiff_t receive(scope void[] buffer)
    {
        logTrace(format!"Receiving bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.receive(buffer);

        if (result == socketERROR)
            detectTimeout();

        logTrace(format!"Received bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }

    /++
        Reads received data into the provided buffer

        Returns:
            Slice of buffer containing the received data.

            Length of `0` indicates that the connection has been closed

        Throws:
            $(LIST
                * [SocketTimeoutException] on timeout
                * [SocketException] on failure
            )
     +/
    T[] receiveSlice(T)(return scope T[] buffer)
            if (is(T == void) || is(T == ubyte) || is(T == char))
    {
        ptrdiff_t bytesReceived = this.receive(buffer);

        if (bytesReceived == socketERROR)
            throw new SocketException("An error occured while receiving data");

        return buffer[0 .. bytesReceived];
    }

    /++
        Fills the whole provided buffer with received data

        Returns:
            Slice of buffer containing the received data.

            Length of `0` indicates that the connection has been closed

        Throws:
            $(LIST
                * [SocketUnexpectedEndOfDataException] if there wasn't enough data to fill the whole buffer
                * [SocketTimeoutException] on timeout
                * [SocketException] on failure
            )
     +/
    T[] receiveAll(T)(return scope T[] buffer)
            if (is(T == void) || is(T == ubyte) || is(T == char))
    {
        ptrdiff_t bytesReceived = 0;
        T[] bufferLeft = buffer;

        while (bufferLeft.length > 0)
        {
            bytesReceived = this.receive(bufferLeft);

            if (bytesReceived == socketERROR)
                throw new SocketException("An error occured while receiving data");

            if (bytesReceived == 0)
            {
                throw new SocketUnexpectedEndOfDataException(
                    "Connection was closed before all of the provided buffer could have been filled"
                );
            }

            bufferLeft = bufferLeft[bytesReceived .. $];
        }

        return buffer;
    }

    /++
        Sends data on the connection

        Returns:
            number of bytes sent

            or [socketplate.connection.socketERROR|socketERROR] on failure

        Throws:
            $(LIST
                * [SocketTimeoutException] on timeout
                * [SocketException] on failure
            )
     +/
    ptrdiff_t send(scope const(void)[] buffer)
    {
        logTrace(format!"Sending bytes (#%X)"(_socket.handle));
        immutable ptrdiff_t result = _socket.send(buffer);

        if (result == socketERROR)
            detectTimeout();

        logTrace(format!"Sent bytes: %d (#%X)"(result, _socket.handle));
        return result;
    }

    /++
        Sends all data from the passed slice on the connection

        Throws:
            [SocketException] on failure
     +/
    void sendAll(scope const(void)[] buffer)
    {
        ptrdiff_t bytesSent = 0;
        const(void)[] bufferLeft = buffer;

        while (bufferLeft.length > 0)
        {
            bytesSent = this.send(bufferLeft);

            if (bytesSent < 0)
                throw new SocketException("An error occured while sending data");

            bufferLeft = bufferLeft[bytesSent .. $];
        }
    }

    ///
    Address remoteAddress()
    {
        return _socket.remoteAddress;
    }

    ///
    Address localAddress()
    {
        return _socket.localAddress;
    }

    ///
    string popCurrentError()
    {
        return _socket.getErrorText();
    }

    ///
    long timeout(Direction direction)()
            if (direction == Direction.send || direction == Direction.receive)
    {
        return _socket.getTimeout!direction();
    }

    ///
    void timeout(Direction direction)(long seconds) if (direction != Direction.none)
    {
        return _socket.setTimeout!direction(seconds);
    }
}

unittest
{
    ubyte[] bufferDyn;
    ubyte[4] bufferStat;

    // dfmt off
    static assert(__traits(compiles, (SocketConnection sc) => sc.sendAll(bufferDyn)));
    static assert(__traits(compiles, (SocketConnection sc) => sc.sendAll(bufferStat)));

    static assert(__traits(compiles, (SocketConnection sc) { ubyte[] r = sc.receiveSlice(bufferDyn); }));
    static assert(__traits(compiles, (SocketConnection sc) { ubyte[] r = sc.receiveSlice(bufferStat); }));

    static assert(__traits(compiles, (SocketConnection sc) { ubyte[] r = sc.receiveAll(bufferDyn); }));
    static assert(__traits(compiles, (SocketConnection sc) { ubyte[] r = sc.receiveAll(bufferStat); }));

    static assert( __traits(compiles, (SocketConnection sc) { long t = sc.timeout!(Direction.receive); }));
    static assert( __traits(compiles, (SocketConnection sc) { long t = sc.timeout!(Direction.send); }));
    static assert(!__traits(compiles, (SocketConnection sc) { long t = sc.timeout!(Direction.both); }));
    static assert(!__traits(compiles, (SocketConnection sc) { long t = sc.timeout!(Direction.none); }));

    static assert( __traits(compiles, (SocketConnection sc) { sc.timeout!(Direction.both) = 90; }));
    static assert( __traits(compiles, (SocketConnection sc) { sc.timeout!(Direction.receive) = 90; }));
    static assert( __traits(compiles, (SocketConnection sc) { sc.timeout!(Direction.send) = 90; }));
    static assert(!__traits(compiles, (SocketConnection sc) { sc.timeout!(Direction.none) = 90; }));
    // dfmt on
}

private void detectTimeout(string file = __FILE__, size_t line = __LINE__)
{
    version (Posix)
    {
        import core.stdc.errno;

        if (errno() == EAGAIN)
            throw new SocketTimeoutException(file, line);
    }
    else version (Window)
    {
        import core.sys.windows.winsock2 : WSAETIMEDOUT, WSAGetLastError;

        if (WSAGetLastError() == WSAETIMEDOUT)
            throw new SocketTimeoutException(file, line);
    }
}

///
class SocketTimeoutException : SocketException
{
    public this(string file = __FILE__, size_t line = __LINE__) @safe pure nothrow @nogc
    {
        super("Socket operation timed out", file, line);
    }
}

///
class SocketUnexpectedEndOfDataException : SocketException
{
    public this(string message, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow @nogc
    {
        super(message, file, line);
    }
}

///
enum Direction
{
    ///
    none = 0b00, ///
    receive = 0b01, ///
    send = 0b10, ///
    both = (receive | send),
}

private
{
    long getTimeout(Direction direction)(Socket socket)
            if (direction == Direction.send || direction == Direction.receive)
    {
        import std.datetime : Duration;

        enum SocketOption sockOpt = (direction == Direction.send)
            ? SocketOption.RCVTIMEO : SocketOption.RCVTIMEO;

        Duration result;
        socket.getOption(SocketOptionLevel.SOCKET, sockOpt, result);
        return result.total!"seconds";
    }

    void setTimeout(Direction direction)(Socket socket, long seconds)
            if (direction != Direction.none)
    {
        import std.datetime : durSeconds = seconds;

        static if (direction == Direction.both)
        {
            setTimeout!(Direction.send)(socket, seconds);
            setTimeout!(Direction.receive)(socket, seconds);
        }
        else static if (direction == Direction.receive)
        {
            logTrace(format!"Setting receive timeout to %d seconds (#%X)"(seconds, socket.handle));
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, durSeconds(seconds));
        }
        else static if (direction == Direction.send)
        {
            logTrace(format!"Setting send timeout to %d seconds (#%X)"(seconds, socket.handle));
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, durSeconds(seconds));
        }
        else
            static assert(false, "Bug");
    }
}
