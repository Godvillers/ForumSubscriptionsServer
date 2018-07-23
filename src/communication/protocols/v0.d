module communication.protocols.v0;

import std.array;
import vibe.data.json;

import communication.protocols.iface;
import communication.protocols.utils;
import cmds = communication.commands;

private @safe:

struct _Corrupted {
    Json toJson() const { return Json.emptyObject; }

    static _Corrupted fromJson(Json src) nothrow pure @nogc {
        assert(false, "Deserializing `Corrupted` is not implemented");
    }
}

// `v0` shall not ever change, so we don't declare our own structures.
alias _Outgoing(T: cmds.Protocol)         = T;
alias _Outgoing(T: cmds.Corrupted)        = _Corrupted;
alias _Outgoing(T: cmds.UnknownCmd)       = T;
alias _Outgoing(T: cmds.InvalidStructure) = T;

enum _keyword(_: cmds.Protocol)         = "protocol";
enum _keyword(_: _Corrupted)            = "corrupted";
enum _keyword(_: cmds.UnknownCmd)       = "unknown";
enum _keyword(_: cmds.InvalidStructure) = "invalidStructure";

public class Codec: IProtocolCodec {
    enum version_ = 0;

    alias parse = IProtocolCodec.parse;

    override cmds.IncomingCommand parse(string cmd, const Json args) const {
        if (cmd == "protocol")
            return cmds.IncomingCommand(deserializeJson!(cmds.Protocol)(args));
        return cmds.IncomingCommand(cmds.UnknownCmd(cmd));
    }

    override void stringify(ref Appender!(char[ ]) sink, const cmds.OutgoingCommand cmd) const {
        import std.traits;

        import sumtype;
        import vibe.core.log;

        cmd.match!(
            (x) {
                alias Schema = _Outgoing!(typeof(x));
                sink._serialize!(Schema, _keyword!(Unqual!Schema))(x);
            },
            x => logWarn("Ignoring an outgoing %s", x),
        );
    }
}

@system unittest {
    import communication.protocols.test;

    mixin _setUp!Codec;
    () @safe {
        expect(q{{"cmd": "nop"}}, cmds.UnknownCmd("nop"));
        expect!(cmds.InvalidStructure)(q{{"cmd": "protocol"}});
        expect!(cmds.InvalidStructure)(q{{"cmd": "protocol", "args": null}});
        expect!(cmds.InvalidStructure)(q{{"cmd": "protocol", "args": { }}});
        expect!(cmds.InvalidStructure)(q{{"cmd": "protocol", "args": {"version": null}}});
        expect!(cmds.InvalidStructure)(q{{"cmd": "protocol", "args": {"version": "1"}}});
        expect(q{{"cmd": "protocol", "args": {"version": 0}}}, cmds.Protocol(0));
        expect(q{{"cmd": "protocol", "args": {"version": 1}}}, cmds.Protocol(1));
        expect(q{{"cmd": "protocol", "args": {"version": -1}}}, cmds.Protocol(-1)); // Should pass.
    }();
}
