module logic.domain_handler;

import std.datetime.systime;
import ordered_aa;

@safe:

struct Topic {
    int posts;
    SysTime lastUpdated;
    bool[size_t] clients; // bool[cast(size_t)ClientHandler*]

    this(this) pure {
        clients = clients.dup;
    }
}

struct DomainHandler {
    OrderedAA!(int, Topic) topics;
}
