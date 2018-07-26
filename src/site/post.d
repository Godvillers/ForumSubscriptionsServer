module site.post;

import vibe.http.server;

void handlePost(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    import std.array;
    import std.exception;
    import std.range;

    import vibe.data.json;

    import logic.client_handler;
    import site.validation;
    import utils;
    import cmds = communication.commands;
    import global = logic.global_handler;

    const char[ ] domain = req.form.get("domain");
    if (!isValidDomainName(domain))
        throw new HTTPStatusException(HTTPStatus.badRequest, "Invalid `domain` POST parameter.");
    const data = req.form.get("data");
    if (data.empty)
        throw new HTTPStatusException(HTTPStatus.badRequest, "Missing `data` POST parameter.");

    res.headers["Access-Control-Allow-Origin"] = "*";

    // This object must not be moved.
    auto clientHandler = ClientHandler(global.registerDomain(domain));

    auto app = appender!(char[ ]);
    app.reserve(128);
    Json[ ] request;
    try
        request = deserializeJson!(Json[ ])(data);
    catch (Exception) {
        const response = [cmds.OutgoingCommand(cmds.Corrupted.init)].s;
        clientHandler.serializeResponse(app, response[ ]);
        goto sendResponse;
    }

    try
        clientHandler.handle(request);
    catch (CommunicationException) { }

    clientHandler.serializeResponse(app);
sendResponse:
    res.writeBody((() @trusted => assumeUnique(app.data))(), "application/json");
}
