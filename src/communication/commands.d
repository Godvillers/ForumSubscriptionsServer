module communication.commands;

import std.typecons: Nullable;

import sumtype;
import vibe.data.json;

import communication.serializable;

@safe:

alias IncomingCommand = SumType!(Protocol, UnknownCmd, ClientConfig, Topics, Confirm, Error);
alias OutgoingCommand = SumType!(
    Protocol, Corrupted, UnknownCmd, ServerConfig, Topics, Confirmation, Error,
);

struct Protocol {
    int version_;
}

struct Corrupted {
    Json toJson() const { return Json.emptyObject; }

    static Corrupted fromJson(Json src) {
        import std.json;

        if (src == Json(null) || src == Json.emptyObject)
            return Corrupted.init;
        throw new JSONException("Cannot deserialize a `Corrupted` from JSON");
    }
}

struct UnknownCmd {
    string cmdName;
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

struct Error {
    string kind, details, msg;
}
