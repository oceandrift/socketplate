/++
    socketplate – “app entry point” helper module

    Also provides all necessary $(I public imports) to quickstart coding.

    ## Developer manual

    Hello and welcome to socketplate.

    ### How to get started

    socketplate.app provides to entry points:

    $(LIST
        * Single connection handler
        * Manual handler setup
    )

    Both come with batteries included:

    $(LIST
        * Several command-line configuration options (worker count etc.)
        * Built-in `--help` parameter
        * Privilege dropping (on POSIX)
        * Specify a custom app name
        * Custom tuning of the socket server (see [socketplate.server.server.SocketServerTunables])
    )

    All that’s left to do is to pick either of the entry points
    and call the corresponding `runSocketplateApp` overload from your `main()` function.

    #### Single connection handler

    In this mode listening addresses are read from `args`
    that will usually point to the program’s command line args.

    This way, an end-user can specify listening addresses by passing `-S <socket>` parameters.

    ```
    $ ./your-app --S 127.0.0.1:8080
    $ ./your-app --S [::1]:8080
    $ ./your-app
    ```

    Sample code:

    ---
    import socketplate.app;

    int main(string[] args)
    {
        return runSocketplateApp("my app", args, (SocketConnection connection) {
            // your code here…
        });
    }
    ---

    There’s no need to give up $(B default listening addresses) either.
    Provide an array of them as the 4th parameter of the `runSocketplateApp` function.
    If default listening addresses are provided, the server will use them when non are specified through `args`.

    ---
    string[] defaultListeningAddresses = [
        "127.0.0.1:8080",
        "[::1]:8080",
    ];

    return runSocketplateApp("my app", args, (SocketConnection connection) {
        // your code here…
    }, defaultListeningAddresses);
    ---

    #### Manual handler setup

    This variation allows you to setup listeners through code instead.

    Code sample:

    ---
    import socketplate.app;

    int main(string[] args)
    {
        return runSocketplateApp("my app", args, (SocketServer server)
        {
            server.listenTCP("127.0.0.1:8080", (SocketConnection connection){
                // listener 1
                // your code here…
            });

            server.listenTCP("[::1]:8080", (SocketConnection connection) {
                // listener 2
                // your code here…
            });
        });
    }
    ---

    In practice you might want to use callback variables
    and reuse them across listeners:

    ---
    return runSocketplateApp("my app", args, (SocketServer server)
    {
        ConnectionHandler myConnHandler = (SocketConnection connection) {
            // your code here…
        };

        server.listenTCP("127.0.0.1:8080", myConnHandler);
        server.listenTCP(    "[::1]:8080", myConnHandler);
    }
    ---

    ### Connection usage

    Established connections are made available as [socketplate.connection.SocketConnection].

    To close a connection, simply call `.close()` on it.

    $(TIP
        Forgetting to close connections is nothing to worry about, though.
        Socketplate’s workers will close still-alive connctions once a connection handler exits.
    )

    #### Sending

    Sending data is super easy:

    ---
    delegate(SocketConnection connection)
    {
        ptrdiff_t bytesSent = connection.send("my data");
    }
    ---

    #### Receiving

    Received data is retrieved via user-provided buffers.

    ---
    delegate(SocketConnection connection)
    {
        // allocate a new buffer (with a size of 256 bytes)
        ubyte[] buffer = new ubyte[](256)

        // read data into the buffer
        auto bytesReceived = connection.receive(buffer);

        if (bytesReceived <= 0) {
            // connection either got closed or timed out,
            // or an error ocurred
            return;
        }

        // slice the buffer (to view only the received data)
        ubyte[] data = buffer[0 .. bytesReceived];

        // do something…
    }
    ---

    ---
    delegate(SocketConnection connection)
    {
        // allocate a new buffer (with a size of 256 bytes)
        ubyte[] buffer = new ubyte[](256)

        // read data into the buffer
        // note: `receiveSlice` throws on error
        ubyte[] data = connection.receiveSlice(buffer);

        if (data.length == 0) {
            // nothing received, connection got closed remotely
            return;
        }

        // do something…
    }
    ---

    ### Logging

    See [socketplate.log] for details.

    ---
    logInfo("My log message");
    ---
 +/
module socketplate.app;

import socketplate.server;
import std.format : format;
import std.getopt;

public import socketplate.address;
public import socketplate.connection;
public import socketplate.log;
public import socketplate.server.server;
public import socketplate.server.tunables;

@safe:

/++
    socketplate quickstart app entry point

    ---
    int main(string[] args) {
        return runSocketplateApp("my app", args, (SocketServer server) {
            server.listenTCP("127.0.0.1:8080", (SocketConnection connection) {
                // IPv4
            });
            server.listenTCP("[::1]:8080", (SocketConnection connection) {
                // IPv6
            });
        });
    }
    ---

    ---
    int main(string[] args) {
        return runSocketplateApp("my app", args, (SocketConnection connection) {
            // listening addresses are read from `args`
        });
    }
    ---
 +/
int runSocketplateApp(
    string appName,
    string[] args,
    void delegate(SocketServer) @safe setupCallback,
    SocketServerTunables serverDefaults = SocketServerTunables(),
) {
    // “Manual handler setup” mode
    return runSocketplateAppImpl(appName, args, setupCallback, serverDefaults);
}

/// ditto
int runSocketplateApp(
    string appName,
    string[] args,
    ConnectionHandler tcpConnectionHandler,
    const string[] defaultListeningAddresses = null,
    void delegate(SocketAddress) @safe foreachListeningAddress = null,
    SocketServerTunables serverDefaults = SocketServerTunables(),
) {
    // “Single connection handler” mode

    // This function adds a “listening addresses” parameter `-S` (aka `--serve`) to getopt options.
    // Also provides a special setup-callback that sets up listeners
    // for the listening addresses retrieved via getopt.
    // As fallback, it resorts to `defaultListeningAddresses`.

    // getopt target
    string[] sockets;

    // setup listeners for the requested listening addresses (or default addresses)
    auto setupCallback = delegate(SocketServer server) @safe {
        // no listening address requested?
        if (sockets.length == 0) {
            // no default address(es) provided?
            if (defaultListeningAddresses.length == 0) {
                logError("No listening address specified. Use parameter `--serve=<addr>` to pass them.");
                return;
            }

            // use default address(es) instead
            foreach (sockAddr; defaultListeningAddresses) {
                SocketAddress parsed;
                if (!parseSocketAddress(sockAddr, parsed)) {
                    assert(false, "Invalid default listening-address: `" ~ sockAddr ~ "`");
                }

                logTrace("Will listen on default address: " ~ sockAddr);

                server.listenTCP(parsed, tcpConnectionHandler);
                if (foreachListeningAddress !is null) {
                    foreachListeningAddress(parsed);
                }
            }

            return;
        }

        // parse requested listening addresses and register listeners
        foreach (socket; sockets) {
            SocketAddress parsed;
            if (!parseSocketAddress(socket, parsed)) {
                throw new Exception("Invalid listening address: `" ~ socket ~ "`");
            }

            final switch (parsed.type) with (SocketAddress.Type) {
            case invalid:
                assert(false);
            case unixDomain:
                break;
            case ipv4:
            case ipv6:
                if (parsed.port <= 0)
                    throw new Exception(
                        "Invalid listening address (invalid/missing port): `" ~ socket ~ "`"
                    );
                break;
            }

            server.listenTCP(parsed, tcpConnectionHandler);
            if (foreachListeningAddress !is null) {
                foreachListeningAddress(parsed);
            }
        }
    };

    return runSocketplateAppImpl(
        appName,
        args,
        setupCallback,
        serverDefaults,
        "S|serve", "Socket(s) to listen on", &sockets
    );
}

/// ditto
deprecated("Use `runSocketplateApp()` instead.") int runSocketplateAppTCP(
    string appName,
    string[] args,
    ConnectionHandler tcpConnectionHandler,
    const string[] defaultListeningAddresses = null,
    SocketServerTunables serverDefaults = SocketServerTunables(),
) {
    return runSocketplateApp(
        appName,
        args,
        tcpConnectionHandler,
        defaultListeningAddresses,
        null,
        serverDefaults,
    );
}

private {
    int runSocketplateAppImpl(Opts...)(
        string appName,
        string[] args,
        void delegate(SocketServer) @safe setupCallback,
        SocketServerTunables serverDefaults,
        Opts opts,
    ) {
        int workers = int.min;
        int workersMax = int.min;
        string strategy = null;
        string username = null;
        string groupname = null;
        bool verbose = false;

        // process `args` (usually command line options)
        GetoptResult getOptR;
        try {
            getOptR = getopt(
                args,
                opts,
                "w|workers", "Number of workers to start", &workers,
                "m|workers-max", "Maximum number of workers to spawn", &workersMax,
                "strategy", "Spawning-strategy applied when starting workers", &strategy,
                "u|user", "(Privileges dropping) user/uid", &username,
                "g|group", "(Privileges dropping) group/gid", &groupname,
                "v|verbose", "Enable debug output", &verbose,
            );
        } catch (GetOptException ex) {
            import std.stdio : stderr;

            // bad option (or similar issue)
            (() @trusted { stderr.writeln(ex.message); })();
            return 1;
        }

        // `--help`?
        if (getOptR.helpWanted) {
            defaultGetoptPrinter(appName, getOptR.options);
            return 0;
        }

        // set log level (`--verbose`?)
        LogLevel logLevel = (verbose) ? LogLevel.trace : LogLevel.info;
        setLogLevel(logLevel);

        // apply caller-provided defaults
        SocketServerTunables serverTunables = serverDefaults;

        // apply `--workers` if applicable
        if (workers != int.min) {
            if (workers < 1) {
                logCritical(format!"Invalid --workers count: %d"(workers));
                return 1;
            }

            serverTunables.listenerDefaults.workers = workers;
        }

        // apply `--workers-max` if applicable
        if (workersMax != int.min) {
            if (workersMax < 1) {
                logCritical(format!"Invalid --workers-max count: %d"(workersMax));
                return 1;
            }

            serverTunables.listenerDefaults.workersMax = workersMax;

            // assume strategy
            if (strategy is null) {
                serverTunables.listenerDefaults.workerSpawningStrategy = SpawningStrategy.dynamic;
            }
        }

        // apply `--strategy` if applicable
        if (strategy !is null) {
            switch (strategy) {
            default:
                logCritical(format!"Invalid --strategy: %s"(strategy));
                return 1;

            case "static":
                serverTunables.listenerDefaults.workerSpawningStrategy = SpawningStrategy.static_;
                break;

            case "dynamic":
                serverTunables.listenerDefaults.workerSpawningStrategy = SpawningStrategy.dynamic;
                break;
            }
        }

        // print app name before further setup
        logInfo(appName);
        auto server = new SocketServer(serverTunables);

        // do setup, if non-null callback provided
        if (setupCallback !is null) {
            try {
                setupCallback(server);
            } catch (Exception ex) {
                logTrace("Unhandled exception thrown in setup callback");
                logError(ex.msg);
                return 1;
            }
        }

        // bind to listening ports
        server.bind();

        // drop privileges
        if (!dropPrivs(username, groupname)) {
            return 1;
        }

        // let’s go
        return server.run();
    }

    bool dropPrivs(string username, string groupname) {
        import socketplate.privdrop;

        version (Posix) {
            auto privilegesDropTo = Privileges();

            // user specified?
            if (username !is null) {
                uid_t uid;
                if (!resolveUsername(username, uid)) {
                    logCritical(format!"Could not resolve username: %s"(username));
                    return false;
                }

                privilegesDropTo.user = uid;
            }

            // group specified?
            if (groupname !is null) {
                gid_t gid;
                if (!resolveGroupname(groupname, gid)) {
                    logCritical(format!"Could not resolve groupname: %s"(groupname));
                    return false;
                }

                privilegesDropTo.group = gid;
            }

            // log applicable target user + group
            if (!privilegesDropTo.user.isNull) {
                logInfo(format!"Dropping privileges: uid=%d"(privilegesDropTo.user.get));
            }
            if (!privilegesDropTo.group.isNull) {
                logInfo(format!"Dropping privileges: gid=%d"(privilegesDropTo.group.get));
            }

            // drop privileges
            if (!dropPrivileges(privilegesDropTo)) {
                // oh no
                logCritical("Dropping privileges failed.");
                return false;
            }

            // warn if running as “root”
            Privileges current = currentPrivileges();

            enum uid_t rootUid = 0;
            enum gid_t rootGid = 0;

            if (current.user.get == rootUid) {
                logWarning("Running as uid=0 (superuser/root)");
            }
            if (current.group.get == rootGid) {
                logWarning("Running as gid=0 (superuser/root)");
            }

            return true;
        } else {
            // privilege dropping not implemented on this platform (e.g. on Windows)

            if (username !is null) {
                logCritical("Privilege dropping is not supported (on this platform).");
                return false;
            }

            if (groupname !is null) {
                logCritical("Privilege dropping is not supported (on this platform).");
                return false;
            }
        }
    }
}
