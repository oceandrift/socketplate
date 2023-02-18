/++
    Logging

    While D standard library’s `std.logger` “implements logging facilities”
    (At the time of writing, this is its actual module description.),
    this modules makes sense of them.

    ---
    import socketplate.log;

    log("Hello world"); // prints a log message with text “Hello world”
    ---


    ## Log levels

    ---
    // set the log level of `sharedLog` to *INFO*
    // (`sharedLog` is the globally available default logger implemented in `std.logger`)
    setLogLevel(LogLevel.info);

    logTrace("Trace/debug message");
    logInfo("Info message");
    logWarning("Warning message");
    logError("(Non-fatal, uncritical) error message");
    logCritical("(Non-fatal yet critical) error message");
    logFatalAndCrash("Fatal error message, also crashes the program");
    ---


    ## Notable differences to `std.logger`

    $(LIST
        * The “default” log functions applys a log level of *INFO* instead of *ALL*.
        * Logging function names are prefixed with `log`.
        * The “fatal”-level logging function mentions in its name that it will crash the application.
        * The hello-world example will actually print a log message out of the box.
    )
 +/
module socketplate.log;

import std.logger : defaultLogFunction;
public import std.logger : LogLevel;

@safe:

/// Logs a trace/debug message
alias logTrace = defaultLogFunction!(LogLevel.trace);

/// Logs an informational message
alias logInfo = defaultLogFunction!(LogLevel.info);

/// Logs a warning
alias logWarning = defaultLogFunction!(LogLevel.warning);

/// Logs an non-critical error
alias logError = defaultLogFunction!(LogLevel.error);

/// Logs a critical error
alias logCritical = defaultLogFunction!(LogLevel.critical);

/// Logs a fatal error and raises an Error to halt execution by crashing the application
alias logFatalAndCrash = defaultLogFunction!(LogLevel.fatal);

///
alias log = logInfo;

/++
    Sets the [LogLevel] of the default logger (also known as `sharedLog`)
 +/
void setLogLevel(LogLevel logLevel)
{
    import std.logger : Logger, sharedLog;

    Logger l = (() @trusted { return (cast() sharedLog); })();
    l.logLevel = logLevel;
}
