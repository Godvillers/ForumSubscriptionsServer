import vibe.vibe;

private @safe:

string[2] _addresses = ["::1", "127.0.0.1"];
ushort _port = 8000;

void _parseArguments() @system {
    readOption("p|port", &_port, "Port to listen to (default: 8000).");
}

void _configure() {
    import core.time;
    import site;

    setLogFormat(FileLogger.Format.threadTime, FileLogger.Format.threadTime);

    auto settings = new HTTPServerSettings;
    settings.bindAddresses = _addresses[ ];
    settings.port = _port;
    settings.webSocketPingInterval = 3.minutes;

    listenHTTP(settings,
        new URLRouter()
        .get("/", &handleIndex)
        .get("/ws", &handleWS)
        .match(HTTPMethod.OPTIONS, "/ws", &handleCORSOptions!"GET")
        .get("/version", serveStaticFile("static/version.txt"))
    );
}

public int main() @system {
    import std.encoding;

    version (DigitalMars) {
        import etc.linux.memoryerror;

        static if (__traits(compiles, &registerMemoryErrorHandler))
            registerMemoryErrorHandler();
    }

    try {
        _parseArguments();
        if (!finalizeCommandLineOptions())
            return 0;
    } catch (Throwable th) {
        logFatal("Error processing command line: %s", th.msg);
        logDiagnostic("%s", th.toString().sanitize());
        return 2;
    }

    try
        _configure();
    catch (Throwable th) {
        logFatal("Configuration error: %s", th.msg);
        logDiagnostic("%s", th.toString().sanitize());
        return 4;
    }

    try {
        lowerPrivileges();
        return runEventLoop();
    } catch (Throwable th) {
        logFatal("%s", th.msg);
        logDiagnostic("%s", th.toString().sanitize());
        return 1;
    }
}
