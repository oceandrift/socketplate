/++
    socketplate server

    ## Maintainer manual

    If you’re looking forward to work on this library itself (or create your own socket server with it),
    this documentation will probably be interesting for you.

    $(NOTE
        If you’re just using socketplate “the regular way”, there won’t be much interesting info here.

        You might like to read through it, when you want to learn more about the technical details of this library.
        Otherwise feel free to skip the following chapters.
    )

    ### Architecture

    The central point of service is the [socketplate.server.server.SocketServer|SocketServer|].
    Listeners are registered on it.

    Once all listeners are registered, bind to the listening addresses via [socketplate.server.server.SocketServer.bind|SocketServer.bind].

    Workers are spawned automatically as needed by [socketplate.server.server.SocketServer.run|SocketServer.run].
    This function enables listening on all sockets as well.

    #### Server + main thread

    The server will usually run from the main thead.

    $(TIP
        If it is supposed run from another thread,
        either disable signal handler setup (see Tunables)
        or forward SIGINT and SIGTERM to the server thread (see [socketplate.signal.forwardSignal()]).
    )

    After starting the worker threads, the server will join them.
    It will eventually exit, once all workers have stopped.
    Unhandled exceptions in any of the workers will be indicated by `SocketServer.run` returning a non-zero status value.
    Obviously they cannot be rethrown by server as this would probably crash the whole server,
    despite Exceptions not being meant to signal logic errors.

    If signal handling is enabled, the server will initiate a graceful shutdown on SIGINT and SIGTERM.
    Those signals get forwarded to worker threads, so that they can gracefully close sockets as well.
    This is especially relevant for accepted sockets (that execute their connection handlers).

    #### Workers

    Workers are implemented as $(B threads).

    $(SIDEBAR
        $(B Forking) as alternative to the used $(B threading) approach was taken into consideration.
        The author came to the conclusion that offering different multi-tasking options
        would just introduce a lot of complexity to consider (downstream as well).
        Threading has to advantage to be available cross-platform as opposed to forking
        that is unavailable on the widely used Win32/Win64.
    )

    As socketplate uses blocking IO, individual workers are spawned for each listener.

    Total number of workers = `listeners × tunables.workers`

    The `shutdown` method of workers is used for graceful shutdown of them.

    The [socketplate.server.worker|worker module] relies a lot on `module private` functions.

    #### Listeners

    [socketplate.server.worker.SocketListener|SocketListener|] is a wrapper for the “listening socket”
    shared across workers.

    `bind` + `listen` are called by the server before starting the workers.

    `accept` is called in the worker’s loop until the worker is shut down.

    `ensureShutdownClosed`
    is called by the worker before exiting
    and shuts down and closes the listener’s socket (if still open).

    `shutdownAccepted`
    shuts down and closes the worker’s (in fact: listener’s) currently accepted connection if applicable.
 +/
module socketplate.server;

public import socketplate.server.pool;
public import socketplate.server.server;
public import socketplate.server.tunables;
public import socketplate.server.worker;
