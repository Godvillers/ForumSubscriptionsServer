module communication.commands;

import std.typecons: Nullable;

import sumtype;

import communication.serializable;

@safe:

alias IncomingCommand = SumType!(
    UnknownCmd, InvalidStructure,
    Protocol, ClientConfig, Topics, Confirm,
);

alias OutgoingCommand = SumType!(
    Corrupted, UnknownCmd, InvalidStructure,
    Protocol, ServerConfig, Topics, Confirmation,
);

struct Protocol {
    int version_;
}

struct Corrupted { }

struct UnknownCmd {
    string cmdName;
}

struct InvalidStructure {
    string details;
}

struct ClientConfig {
    Nullable!(int[ ]) subs; // We must be able to tell `null` apart from `[ ]`.
    Ternary shareSubs;
}

struct ServerConfig {
    int[ ] extraSubs;
}

struct Topic {
    int id, posts;
    SysTime timestamp;
}

struct Topics {
    Topic[ ] data;

    alias data this;
}

struct Confirm {
    IncomingCommand* wrapped;
}

struct Confirmation {
    string status;
}
