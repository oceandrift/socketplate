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

    The `shutdown` method of workers will be used for graceful shutdown in the future.

    #### Listeners

    [socketplate.server.worker.SocketListener|SocketListener|] is a wrapper for the “listening socket”
    shared across workers.

    `bind` + `listen` are called by the server before starting the workers.

    `accept` is called in the worker’s loop until the worker is shut down.

    `ensureShutdownClosed` is called by the server before exiting
    and shuts down and closes the listener’s socket (if still open).
 +/
module socketplate.server;

public import socketplate.server.server;
public import socketplate.server.worker;
