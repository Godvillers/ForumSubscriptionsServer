module communication.protocols.v1;

import std.typecons: Nullable;

import vibe.data.json;
import vibe.data.serialization: optional;

import communication.protocols.utils;
import communication.serializable;
import cmds = communication.commands;
import v0 = communication.protocols.v0;

private struct _ClientConfig {
    @optional Nullable!(int[ ]) subs;
    @optional Ternary shareSubs;
}

private struct _Topics {
    cmds.Topic[ ] data;
}

class Parser: v0.Parser {
    enum version_ = 1;

    alias parse = typeof(super).parse;

    override cmds.Command parse(string cmd, const Json args) const @safe {
        switch (cmd) {
        case "config":
            return _deserialize!(cmds.ClientConfig, _ClientConfig)(args);

        case "topics":
            return _deserialize!(cmds.Topics, _Topics)(args);

        case "confirm": {
            auto boxed = new cmds.Command;
            *boxed = parse(args["wrapped"]);
            return cmds.Command(cmds.Confirm(boxed));
        }

        default:
            return super.parse(cmd, args);
        }
    }
}

@system unittest {
    import communication.protocols.test;

    mixin _setUp!Parser;
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
