module site.ws;

import vibe.http.server;

@safe:

void handleWS(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    import std.range;
    import vibe.core.log;
    import vibe.http.websockets;

    const domain = req.query.get("domain");
    if (domain.empty)
        throw new HTTPStatusException(HTTPStatus.badRequest, "Missing `domain` GET parameter.");

    res.headers["Access-Control-Allow-Origin"] = "*";
    handleWebSocket((scope socket) nothrow {
        // TODO.
    }, req, res);
}
