/++
    Signal handling
 +/
module socketplate.signal;

import core.thread : Thread;
import socketplate.log;
import std.string : format;

alias SignalFunc = void delegate(int) nothrow @nogc;

///
void setupSignalHandlers(SignalFunc handler) @safe
in (handler !is null)
{
    logTrace(format!"Setting up signal handlers for thread: 0x%X"(Thread.getThis().id));
    _onSignal = handler;

    version (Posix)
    {
        import core.sys.posix.signal;

        () @trusted {
            signal(SIGINT, &_socketplate_posix_signal_handler);
            signal(SIGTERM, &_socketplate_posix_signal_handler);
        }();
    }
    else
    {
        version (Windows)
        {
            // TODO
            // SetConsoleCtrlHandler(…);
            logError("ConsoleCtrlHandler not implemented yet");
        }
        else
        {
            logError(
                "Signal handlers either not available on or implemented for this platform."
            );
        }
    }
}

///
void forwardSignal(int signal, Thread[] threads) @safe nothrow @nogc
{
    foreach (thread; threads)
        forwardSignal(signal, thread);
}

///
void forwardSignal(int signal, Thread thread) @safe nothrow @nogc
{
    version (Posix)
    {
        import core.sys.posix.pthread;

        immutable bool isRunning = () @trusted { return thread.isRunning(); }();
        if (!isRunning)
            return;

        pthread_t threadID;
        try
            threadID = thread.id;
        catch (Exception)
            return;

        () @trusted { pthread_kill(threadID, signal); }();
    }
    else
    {
        logError("Signal forwarding not implemented on this platform");
    }
}

private
{
    version (Posix)
    {
        // thread local signal handler
        static SignalFunc _onSignal = null;

        extern (C) void _socketplate_posix_signal_handler(int signal) nothrow @nogc
        {
            if (_onSignal is null)
                return;

            return _onSignal(signal);
        }
    }
}
