module communication.commands;

import std.typecons: Nullable;
import sumtype;
import communication.serializable;

// TODO: Split into `IncomingCommand` and `OutgoingCommand`.
alias Command = SumType!(
    Protocol, ClientConfig, ServerConfig, Topics, Confirm, Confirmation, Error,
);

struct Protocol {
    int version_;
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
    Command* wrapped;
}

struct Confirmation {
    string status;
}

struct Error {
    string kind, details, msg;
}
