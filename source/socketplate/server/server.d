/++
    Socket server implementation
 +/
module socketplate.server.server;

import core.thread;
import socketplate.address;
import socketplate.connection;
import socketplate.log;
import socketplate.server.pool;
import socketplate.server.tunables;
import socketplate.server.worker;
import std.format;
import std.socket;

@safe:

///
final class SocketServer
{
@safe:

    private
    {
        SocketServerTunables _tunables;
        bool _shutdown = false;

        SocketListener[] _listeners;
    }

    ///
    public this(SocketServerTunables tunables) pure nothrow @nogc
    {
        _tunables = tunables;
    }

    /// ditto
    public this() pure nothrow @nogc
    {
        this(SocketServerTunables());
    }

    public
    {
        ///
        int run()
        {
            scope (exit)
            {
                logTrace("Exiting (Main Thread)");
            }

            if (_listeners.length == 0)
            {
                logWarning("There are no listeners, hence no workers to spawn.");
                return 0;
            }

            logTrace("Running");
            auto pool = new WorkerPool(_tunables, _listeners);
            return pool.run();
        }

        ///
        void bind(bool socketOptionREUSEADDR = true)
        {
            foreach (listener; _listeners)
                listener.bind(socketOptionREUSEADDR);
        }

        void registerListener(SocketListener listener)
        {
            _listeners ~= listener;
        }
    }
}

/++
    Registers a new TCP listener
 +/
void listenTCP(SocketServer server, Address address, ConnectionHandler handler)
{
    logTrace("Registering TCP listener on ", address.toString);

    ProtocolType protocolType = (address.addressFamily == AddressFamily.UNIX)
        ? cast(ProtocolType) 0 : ProtocolType.TCP;

    auto listener = new SocketListener(
        new Socket(address.addressFamily, SocketType.STREAM, protocolType),
        address,
        handler,
        server._tunables.timeout,
    );

    server.registerListener(listener);
}

/// ditto
void listenTCP(SocketServer server, SocketAddress listenOn, ConnectionHandler handler)
{
    return listenTCP(server, listenOn.toPhobos(), handler);
}

/// ditto
void listenTCP(SocketServer server, string listenOn, ConnectionHandler handler)
{
    SocketAddress sockAddr;
    assert(parseSocketAddress(listenOn, sockAddr), "Invalid listening address");
    return listenTCP(server, sockAddr, handler);
}

// Converts a SocketAddress to an `std.socket.Address`
private Address toPhobos(SocketAddress sockAddr)
{
    try
    {
        final switch (sockAddr.type) with (SocketAddress.Type)
        {
        case unixDomain:
            version (Posix)
                return new UnixAddress(sockAddr.address);
            else
                assert(false, "Unix Domain sockets unavailable");

        case ipv4:
            assert(sockAddr.port > 0);
            return new InternetAddress(sockAddr.address, cast(ushort) sockAddr.port);

        case ipv6:
            assert(sockAddr.port > 0);
            return new Internet6Address(sockAddr.address, cast(ushort) sockAddr.port);

        case invalid:
            assert(false, "Invalid address");
        }
    }
    catch (AddressException ex)
    {
        assert(false, "Invalid address: " ~ ex.msg);
    }
}
