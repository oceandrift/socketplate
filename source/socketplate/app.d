/++
    socketplate

    ## Developer manual

    Hello and welcome to socketplate.
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
    SocketServerTunables defaults = SocketServerTunables(),
)
{
    string[] sockets;
    auto setupCallback = delegate(SocketServer server) @safe {
        if (sockets.length == 0)
        {
            logError("No listening addresses specified. Use --serve= ");
            return;
        }
        foreach (socket; sockets)
        {
            logInfo("ToDo: " ~ socket);
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
