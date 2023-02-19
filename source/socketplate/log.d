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
    Logs an exception (including a stack trace)
 +/
void logException(LogLevel logLevel = LogLevel.error, LogLevel details = LogLevel.trace)(
    Throwable exception,
    string description = "Exception",
    int line = __LINE__,
    string file = __FILE__,
    string funcName = __FUNCTION__,
    string prettyFuncName = __PRETTY_FUNCTION__,
    string moduleName = __MODULE__,
)
@safe nothrow
{
    import std.logger : log;
    import std.string : format;

    try
    {
        log(
            logLevel,
            line, file, funcName, prettyFuncName, moduleName,
            format!"%s: %s"(description, exception.msg)
        );

        try
        {
            log(
                details,
                line, file, funcName, prettyFuncName, moduleName,
                format!"Details: %s"(() @trusted { return exception.toString(); }())
            );
        }
        catch (Exception ex)
        {
            logTrace(format!"Failed to log details: %s"(ex.msg));
        }
    }
    catch (Exception)
    {
        // suppress
    }
}

///
unittest
{
    try
    {
        // …
    }
    catch (Exception ex)
    {
        logException(ex, "Operation XY failed.");
    }

}

///
unittest
{
    try
    {
        // …
    }
    catch (Exception ex)
    {
        logException!(LogLevel.trace)(ex);
    }

}

/++
    Sets the [LogLevel] of the default logger (also known as `sharedLog`)
 +/
void setLogLevel(LogLevel logLevel)
{
    import std.logger : Logger, sharedLog;

    Logger l = (() @trusted { return (cast() sharedLog); })();
    l.logLevel = logLevel;
}
