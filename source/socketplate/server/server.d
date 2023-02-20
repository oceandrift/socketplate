/++
    Socket server implementation
 +/
module socketplate.server.server;

import core.thread;
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
    int backlog = SOMAXCONN;

    /++
        Receive/read timeout
     +/
    int timeout = 60;

    /++
        Number of workers per listener
     +/
    int workers = 2;

    /++
        Whether to set up signal handlers
     +/
    bool setupSignalHandlers = true;
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
            if (_listeners.length == 0)
            {
                logWarning("There are no listeners, hence no workers to spawn.");
                return 0;
            }

            logTrace("Running");
            int x = spawnWorkers();
            logTrace("Exiting (Main Thread)");
            return x;
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

    private
    {
        int spawnWorkers()
        {
            logTrace("Starting SocketServer in Threading mode");

            Thread[] threads;
            Worker[] workers;

            size_t nWorkers = (_listeners.length * _tunables.workers);
            workers.reserve(nWorkers);

            scope (exit)
                foreach (worker; workers)
                    worker.shutdown();

            foreach (SocketListener listener; _listeners)
            {
                listener.listen(_tunables.backlog);

                foreach (i; 0 .. _tunables.workers)
                    threads ~= spawnWorkerThread(threads.length, listener, _tunables, workers);
            }

            // setup signal handlers (if requested)
            if (_tunables.setupSignalHandlers)
            {
                import socketplate.signal;

                setupSignalHandlers(delegate(int signal) @safe nothrow @nogc {
                    // signal threads
                    forwardSignal(signal, threads);
                });
            }

            // start worker threads
            foreach (Thread thread; threads)
                function(Thread thread) @trusted { thread.start(); }(thread);

            bool error = false;

            // wait for workers to exit
            foreach (thread; threads)
            {
                function(Thread thread, ref error) @trusted {
                    try
                        thread.join();
                    catch (Exception)
                        error = true;
                }(thread, error);
            }

            return (error) ? 1 : 0;
        }

        static Thread spawnWorkerThread(
            size_t id,
            SocketListener listener,
            const SocketServerTunables tunables,
            ref Worker[] workers
        )
        {
            auto worker = new Worker(listener, id, tunables.setupSignalHandlers);
            workers ~= worker;
            return new Thread(&worker.run);
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
