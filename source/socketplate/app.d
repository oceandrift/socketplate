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
            // connection closed (or timed out)
            return;
        }

        // slice the buffer (to view only the received data)
        ubyte[] data = buffer[0 .. bytesReceived];

        // do something…
    }
    ---

    ### Logging

    See [socketplate.log] for details.
 +/
module socketplate.app;

import socketplate.server;
import std.format : format;
import std.getopt;

public import socketplate.address;
public import socketplate.connection;
public import socketplate.log;
public import socketplate.server.server;

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
    SocketServerTunables defaults = SocketServerTunables(),
)
{
    return runSocketplateAppImpl(appName, args, setupCallback, defaults);
}

/// ditto
int runSocketplateAppTCP(
    string appName,
    string[] args,
    ConnectionHandler tcpConnectionHandler,
    string[] defaultListeningAddresses = null,
    SocketServerTunables defaults = SocketServerTunables(),
)
{
    string[] sockets;
    auto setupCallback = delegate(SocketServer server) @safe {
        if (sockets.length == 0)
        {
            if (defaultListeningAddresses.length == 0)
            {
                logError("No listening addresses specified. Use --serve= ");
                return;
            }

            foreach (sockAddr; defaultListeningAddresses)
            {
                logTrace("Will listen on default address: " ~ sockAddr);
                server.listenTCP(sockAddr, tcpConnectionHandler);
            }

            return;
        }

        foreach (socket; sockets)
        {
            SocketAddress parsed;
            if (!parseSocketAddress(socket, parsed))
                throw new Exception("Invalid listening address: `" ~ socket ~ "`");

            server.listenTCP(parsed, tcpConnectionHandler);
        }
    };

    return runSocketplateAppImpl(appName, args, setupCallback, defaults, "S|serve", "Socket(s) to listen on", &sockets);
}

private
{
    int runSocketplateAppImpl(Opts...)(
        string appName,
        string[] args,
        void delegate(SocketServer) @safe setupCallback,
        SocketServerTunables defaults,
        Opts opts,
    )
    {
        int workers = int.min;
        string username = null;
        string groupname = null;
        bool verbose = false;

        GetoptResult getOptR;
        try
            getOptR = getopt(
                args,
                opts,
                "w|workers", "Number of workers to start", &workers,
                "u|user", "(Privileges dropping) user/uid", &username,
                "g|group", "(Privileges dropping) group/gid", &groupname,
                "v|verbose", "Enable debug output", &verbose,
            );
        catch (GetOptException ex)
        {
            import std.stdio : stderr;

            (() @trusted { stderr.writeln(ex.message); })();
            return 1;
        }

        if (getOptR.helpWanted)
        {
            defaultGetoptPrinter(appName, getOptR.options);
            return 0;
        }

        LogLevel logLevel = (verbose) ? LogLevel.trace : LogLevel.info;
        setLogLevel(logLevel);

        SocketServerTunables tunables = defaults;

        if (workers != int.min)
        {
            if (workers < 1)
            {
                logCritical(format!"Invalid --workers count: %d"(workers));
                return 1;
            }

            tunables.workers = workers;
        }

        logInfo(appName);
        auto server = new SocketServer(tunables);

        if (setupCallback !is null)
        {
            try
                setupCallback(server);
            catch (Exception ex)
            {
                logTrace("Unhandled exception thrown in setup callback");
                logError(ex.msg);
                return 1;
            }
        }

        server.bind();

        // drop privileges
        if (!dropPrivs(username, groupname))
            return 1;

        return server.run();
    }

    bool dropPrivs(string username, string groupname)
    {
        import socketplate.privdrop;

        version (Posix)
        {
            auto privilegesDropTo = Privileges();

            // user specified?
            if (username !is null)
            {
                uid_t uid;
                if (!resolveUsername(username, uid))
                {
                    logCritical(format!"Could not resolve username: %s"(username));
                    return false;
                }

                privilegesDropTo.user = uid;
            }

            // group specified?
            if (groupname !is null)
            {
                gid_t gid;
                if (!resolveGroupname(groupname, gid))
                {
                    logCritical(format!"Could not resolve groupname: %s"(groupname));
                    return false;
                }

                privilegesDropTo.group = gid;
            }

            // log applicable target user + group
            if (!privilegesDropTo.user.isNull)
                logInfo(format!"Dropping privileges: uid=%d"(privilegesDropTo.user.get));
            if (!privilegesDropTo.group.isNull)
                logInfo(format!"Dropping privileges: gid=%d"(privilegesDropTo.group.get));

            // drop privileges
            if (!dropPrivileges(privilegesDropTo))
            {
                // oh no
                logCritical("Dropping privileges failed.");
                return false;
            }

            // warn if running as “root”
            Privileges current = currentPrivileges();

            enum uid_t rootUid = 0;
            enum gid_t rootGid = 0;

            if (current.user.get == rootUid)
                logWarning("Running as uid=0 (superuser/root)");
            if (current.group.get == rootGid)
                logWarning("Running as gid=0 (superuser/root)");

            return true;
        }
        else
        {
            // privilege dropping not implemented on this platform (e.g. on Windows)

            if (username !is null)
            {
                logCritical("Privilege dropping is not supported (on this platform).");
                return false;
            }

            if (groupname !is null)
            {
                logCritical("Privilege dropping is not supported (on this platform).");
                return false;
            }
        }
    }
}
