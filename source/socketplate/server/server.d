/++
    Socket server implementation
 +/
module socketplate.server.server;

import socketplate.address;
import socketplate.connection;
import socketplate.log;
import socketplate.server.worker;
import std.format;
import std.socket;

@safe:

/++
    Options to tailor the socket server to your needs
 +/
struct SocketServerTunables
{
    /++
        Listening backlog
     +/
    int backlog = 1;

    /++
        Receive/read timeout
     +/
    int timeout = 30;

    /++
        Number of workers per listener
     +/
    int workers = 2;
}

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
    public this(SocketServerTunables tunables)
    {
        _tunables = tunables;
    }

    /// ditto
    public this()
    {
        this(SocketServerTunables());
    }

    public
    {
        ///
        int run()
        {
            if (_listeners.length == 0)
            {
                logWarning("There are no listeners, hence no workers to spawn.");
                return 0;
            }

            logTrace("Running");
            int x = spawnWorkers();
            logTrace("Exiting");
            return x;
        }

        ///
        void bind()
        {
            foreach (listener; _listeners)
                listener.bind();
        }

        void registerListener(SocketListener listener)
        {
            _listeners ~= listener;
        }
    }

    private
    {
        int spawnWorkers()
        {
            import core.thread;

            logTrace("Starting SocketServer in Threading mode");

            Thread[] threads;
            foreach (SocketListener listener; _listeners)
            {
                listener.listen(_tunables.backlog);

                foreach (i; 0 .. _tunables.workers)
                {
                    threads ~= (function(size_t id, SocketListener listener) {
                        return new Thread(() {
                            auto worker = new Worker(listener, id);
                            worker.run();
                        });
                    })(threads.length, listener);
                }
            }

            // TODO: Graceful shutdown

            foreach (Thread thread; threads)
                function(Thread thread) @trusted { thread.start(); }(thread);

            foreach (Thread thread; threads)
                function(Thread thread) @trusted { thread.join(); }(thread);

            return 0; // TODO
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
