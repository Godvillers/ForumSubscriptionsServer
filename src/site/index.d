module site.index;

import vibe.http.server;

void handleIndex(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    res.writeBody("Nothing interesting here, really.\n");
}
