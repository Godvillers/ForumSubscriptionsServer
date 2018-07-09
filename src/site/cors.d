module site.cors;

import vibe.http.server;

@safe:

private void _handle(string method, scope HTTPServerRequest req, scope HTTPServerResponse res) {
    import core.time;
    import std.conv;

    enum oneDay = 24.hours.total!q{seconds}.to!string;
    res.headers["Access-Control-Allow-Origin"] = "*";
    res.headers["Access-Control-Allow-Methods"] = method;
    res.headers["Access-Control-Max-Age"] = oneDay;
    res.writeVoidBody();
}

void handleCORSOptions(string method)(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    _handle("OPTIONS, " ~ method, req, res);
}
