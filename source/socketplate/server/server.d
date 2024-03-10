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
import std.typecons : Nullable;

@safe:

///
final class SocketServer {

@safe:

    private {
        SocketServerTunables _tunables;
        SocketListenerTunables _listenerTunablesDefaults;
        bool _shutdown = false;

        SocketListener[] _listeners;
    }

    ///
    public this(SocketServerTunables tunables, SocketListenerTunables listenerTunablesDefaults) pure nothrow @nogc {
        _tunables = tunables;
        _listenerTunablesDefaults = listenerTunablesDefaults;
    }

    /// ditto
    public this() pure nothrow @nogc {
        this(SocketServerTunables(), SocketListenerTunables());
    }

    public {

        ///
        int run() {
            scope (exit) {
                logTrace("Exiting (Main Thread)");
            }

            if (_listeners.length == 0) {
                logWarning("There are no listeners, hence no workers to spawn.");
                return 0;
            }

            logTrace("Running");
            auto pool = new WorkerPool(_tunables, _listeners);
            return pool.run();
        }

        ///
        void bind(bool socketOptionREUSEADDR = true) {
            foreach (listener; _listeners)
                listener.bind(socketOptionREUSEADDR);
        }

        void registerListener(SocketListener listener) {
            _listeners ~= listener;
        }
    }
}

///
alias NListenerTunables = Nullable!SocketListenerTunables;

/++
    Nullified [NListenerTunables] used to instruct the server to apply its default tunable settings
    to the the listener that is to be registered.
 +/
enum useServerDefaults = NListenerTunables();

/++
    Registers a new TCP listener
 +/
void listenTCP(
    SocketServer server,
    Address address,
    ConnectionHandler handler,
    NListenerTunables tunables = useServerDefaults,
) {
    logTrace("Registering TCP listener on ", address.toString);

    ProtocolType protocolType = (address.addressFamily == AddressFamily.UNIX)
        ? cast(ProtocolType) 0 : ProtocolType.TCP;

    SocketListenerTunables applicableTunables = (tunables.isNull)
        ? server._listenerTunablesDefaults : tunables.get();

    auto listener = new SocketListener(
        new Socket(address.addressFamily, SocketType.STREAM, protocolType),
        address,
        handler,
        applicableTunables,
    );

    server.registerListener(listener);
}

/// ditto
void listenTCP(
    SocketServer server,
    SocketAddress listenOn,
    ConnectionHandler handler,
    NListenerTunables tunables = useServerDefaults,
) {
    return listenTCP(server, listenOn.toPhobos(), handler, tunables);
}

/// ditto
void listenTCP(
    SocketServer server,
    string listenOn,
    ConnectionHandler handler,
    NListenerTunables tunables = useServerDefaults,
) {
    SocketAddress sockAddr;
    assert(parseSocketAddress(listenOn, sockAddr), "Invalid listening address");
    return listenTCP(server, sockAddr, handler, tunables);
}

// Converts a SocketAddress to an `std.socket.Address`
private Address toPhobos(SocketAddress sockAddr) {
    try {
        final switch (sockAddr.type) with (SocketAddress.Type) {
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
    } catch (AddressException ex) {
        assert(false, "Invalid address: " ~ ex.msg);
    }
}
