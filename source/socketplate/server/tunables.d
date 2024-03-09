/++
    Server settings
 +/
module socketplate.server.tunables;

import std.socket : SOMAXCONN;

/++
    Options to tailor the socket server to your needs
 +/
struct SocketServerTunables {

    /++
        Defaults to apply to socket listeners registered with the server

        These defaults can be overriden at registration time
        by passing a non-nullified value to the `tunables` parameter
        of [socketplate.server.server.listenTCP|listenTCP()].
     +/
    SocketListenerTunables listenerDefaults = SocketListenerTunables();

    /++
        Whether to set up signal handlers
     +/
    bool setupSignalHandlers = true;
}

/++
    Options to tailor a socket listener to your needs
 +/
struct SocketListenerTunables {

    /++
        Listening backlog
     +/
    int backlog = SOMAXCONN;

    /++
        Receive/read timeout
     +/
    int timeout = 60;

    /++
        The spawning strategy to apply when spawning workers
     +/
    SpawningStrategy workerSpawningStrategy = SpawningStrategy.static_;

    /++
        Number of workers per listener
     +/
    int workers = 2;

    /++
        Maximum number of workers per listener for non-static spawning-strategies
     +/
    int workersMax = 2;
}

/++
    Strategies to use for spawning workers.

    Each strategy has its own pros and cons.
 +/
enum SpawningStrategy {

    /++
        Static – A fixed number of workers gets spawned.
     +/
    static_,

    /++
        Dynamic – Workers get spawned as needed.

        A configured minimum number of workers gets spawned at start.
        Once all of them are in use, another worker will get spawned
        until the configured upper limit (`workersMax`) is reached.
     +/
    dynamic,
}
