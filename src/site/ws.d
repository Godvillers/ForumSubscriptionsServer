module site.ws;

import core.time;
import std.array;

import vibe.http.server;
import vibe.http.websockets;

import logic.client_handler;
import utils;
import cmds = communication.commands;

private @safe:

enum _extraSubsRefreshInterval = 30.minutes;

// Client -> Server [-> Client].
void _runReader(scope WebSocket socket, ref ClientHandler clientHandler) {
    import vibe.data.json;

    auto app = appender!(char[ ]);
    app.reserve(1024);
    Json[ ] request;
    bool abort;
    while (socket.waitForData()) {
        const text = socket.receiveText();
        try
            request = deserializeJson!(Json[ ])(text);
        catch (Exception) {
            const response = [cmds.OutgoingCommand(cmds.Corrupted.init)].s;
            clientHandler.serializeResponse(app, response[ ]);
            goto sendResponse;
        }

        try
            clientHandler.handle(request);
        catch (CommunicationException)
            abort = true;

        if (clientHandler.serializeResponse(app)) {
            if (app.data.length > 2) { // Unless it is `[]`.
            sendResponse:
                socket.send(app.data);
            }
            app.clear();
        }
        if (abort) {
            socket.close(WebSocketCloseReason.protocolError);
            break;
        }
    }
}

// Server -> Client.
void _runWriter(scope WebSocket socket, ref ClientHandler clientHandler) {
    import std.algorithm.iteration;

    auto app = appender!(char[ ]);
    auto topics = appender!(cmds.Topic[ ]);
    while (true) {
        clientHandler.sleep();
        if (!socket.connected)
            break;

        app.reserve(256);
        topics.reserve(4);
        topics ~=
            clientHandler.queuedTopics
            .joiner()
            .filter!(topic => clientHandler.isSubscribedFor(topic.id));
        clientHandler.clearQueuedTopics(); // Clear immediately.

        const response = [cmds.OutgoingCommand(cmds.Topics(topics.data))].s;
        clientHandler.serializeResponse(app, response[ ]);
        socket.send(app.data);
        app.clear();
        topics.clear();
    }
}

// Server -> Client.
void _runRefresher(scope WebSocket socket, ref ClientHandler clientHandler) {
    import vibe.core.core: sleep;

    auto app = appender!(char[ ]);
    while (true) {
        sleep(_extraSubsRefreshInterval);
        auto extraSubs = clientHandler.chooseExtraSubs();
        if (!extraSubs.empty) {
            const response = [cmds.OutgoingCommand(cmds.ServerConfig(extraSubs))].s;
            app.reserve(192);
            clientHandler.serializeResponse(app, response[ ]);
            socket.send(app.data);
            app.clear();
        }
    }
}

void _disconnect(scope WebSocket socket, string fmt, Exception e) nothrow {
    logStackTrace(fmt, e);
    try
        socket.close(WebSocketCloseReason.internalError);
    catch (Exception) { }
}

void _handleClient(string domain, scope WebSocket socket) {
    import vibe.core.core;
    import logic.domain_handler;
    import global = logic.global_handler;

    // This object must not be moved.
    auto clientHandler = ClientHandler(global.registerDomain(domain));

    auto refresher = runTask({
        try
            _runRefresher(socket, clientHandler);
        catch (InterruptException) { }
        catch (Exception e)
            _disconnect(socket,
                "Unexpected exception during WebSocket handling (refresher): %s", e);
    });
    scope(exit) refresher.interrupt();

    auto writer = runTask({
        try
            _runWriter(socket, clientHandler);
        catch (InterruptException) { }
        catch (Exception e)
            _disconnect(socket, "Unexpected exception during WebSocket handling (writer): %s", e);
    });
    scope(failure) writer.interrupt();

    _runReader(socket, clientHandler);
    clientHandler.wake(null);
    writer.join();
}

public void handleWS(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    import std.range;
    import site.validation;

    const domain = req.query.get("domain");
    if (!isValidDomainName(domain))
        throw new HTTPStatusException(HTTPStatus.badRequest, "Invalid `domain` GET parameter.");

    res.headers["Access-Control-Allow-Origin"] = "*";
    handleWebSocket((scope socket) nothrow @safe {
        try
            _handleClient(domain, socket);
        catch (Exception e)
            _disconnect(socket, "Unexpected exception during WebSocket handling: %s", e);
    }, req, res);
}
