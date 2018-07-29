module communication.protocols.v1;

import std.array;
import std.traits;
import std.typecons: Nullable;

import vibe.data.json;
import vibe.data.serialization: optional;

import communication.protocols.utils;
import communication.serializable;
import cmds = communication.commands;
import v0 = communication.protocols.v0;

private @safe:

struct _ClientConfig {
    @optional Nullable!(int[ ]) subs;
    @optional Ternary shareSubs;
}

struct _Topics {
    @asArray cmds.Topic[ ] data;
}

struct _ServerConfig {
    int[ ] extraSubs;
}

struct _Confirmation {
    string status;
}

struct _Error {
    string kind, details, msg;
}

alias _OutgoingImpl(_: cmds.Topics)       = _Topics;
alias _OutgoingImpl(_: cmds.ServerConfig) = _ServerConfig;
alias _OutgoingImpl(_: cmds.Confirmation) = _Confirmation;
alias _OutgoingImpl(_: cmds.Error)        = _Error;
alias _Outgoing(T) = CopyTypeQualifiers!(T, _OutgoingImpl!(Unqual!T));

enum _keyword(_: _Topics)       = "topics";
enum _keyword(_: _ServerConfig) = "config";
enum _keyword(_: _Confirmation) = "confirmation";
enum _keyword(_: _Error)        = "error";

public class Codec: v0.Codec {
    enum version_ = 1;

    alias parse = typeof(super).parse;

    override cmds.IncomingCommand parse(string cmd, const Json args) const {
        switch (cmd) {
        case "config":
            return _deserialize!(cmds.ClientConfig, _ClientConfig)(args);

        case "topics":
            return _deserialize!(cmds.Topics, _Topics)(args);

        case "confirm": {
            auto boxed = new cmds.IncomingCommand;
            *boxed = parse(args["wrapped"]); // Returns `Json.undefined` if not found.
            return cmds.IncomingCommand(cmds.Confirm(boxed));
        }

        default:
            return super.parse(cmd, args);
        }
    }

    override void stringify(ref Appender!(char[ ]) sink, const cmds.OutgoingCommand cmd) const {
        import sumtype;

        cmd.match!((x) {
            static if (is(_Outgoing!(typeof(x)) Schema))
                sink._serialize!(Schema, _keyword!(Unqual!Schema))(x);
            else
                super.stringify(sink, cmd);
        });
    }
}

@system unittest {
    import communication.protocols.test;

    mixin _setUp!Codec;
    () @safe {
        import sumtype;
        import utils;

        expect(q{{"cmd": "protocol", "args": {"version": 1}}}, cmds.Protocol(1));

        expect(q{{"cmd": "config"}}, cmds.ClientConfig.init);
        expect(
            q{{"cmd": "config", "args": {"subs": [ ]}}},
            cmds.ClientConfig(Nullable!(int[ ])([ ]), Ternary(Ternary.unknown)),
        );
        expect(
            q{{"cmd": "config", "args": {"shareSubs": false}}},
            cmds.ClientConfig(Nullable!(int[ ]).init, Ternary(Ternary.no)),
        );

        parse(q{{
            "cmd": "confirm",
            "args": {
                "wrapped": {
                    "cmd": "topics",
                    "args": {
                        "data": [
                            {"id": 3432, "posts": 3951, "timestamp": 1531046999}
                        ]
                    }
                }
            }
        }}).match!(
            (cmds.Confirm confirm) => (*confirm.wrapped).match!(
                (cmds.Topics topics) {
                    const expected =
                        [cmds.Topic(3432, 3951, SysTime(SysTime.fromUnixTime(1531046999)))].s;
                    assert(topics == expected[ ]);
                },
                _ => unreachable,
            ),
            _ => unreachable,
        );
    }();
}

@system unittest {
    import communication.protocols.test;

    mixin _setUp!Codec;
    () @safe {
        import std.algorithm.comparison;
        import sumtype;
        import utils;

        auto app = appender!(char[ ]);

        codec.stringify(app, cmds.OutgoingCommand(cmds.Protocol(1))); // Forwarded to `v0`.
        assert(app.data.among(
            q{{"cmd":"protocol","args":{"version":1}}},
            q{{"args":{"version":1},"cmd":"protocol"}},
        ), app.data);

        auto topics = [7, 3432].s;
        app.clear();
        codec.stringify(app, cmds.OutgoingCommand(cmds.ServerConfig(topics[ ])));
        assert(app.data.among(
            q{{"cmd":"config","args":{"extraSubs":[7,3432]}}},
            q{{"args":{"extraSubs":[7,3432]},"cmd":"config"}},
        ), app.data);
    }();
}
