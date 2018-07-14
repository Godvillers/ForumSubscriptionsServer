module communication.protocols.v0;

import std.array;
import std.traits;
import vibe.data.json;

import communication.protocols.iface;
import communication.protocols.utils;
import cmds = communication.commands;

private @safe:

struct _Protocol {
    int version_;
}

struct _Error {
    string kind, details, msg;
}

alias _OutgoingImpl(_: cmds.Protocol) = _Protocol;
alias _OutgoingImpl(_: cmds.Error)    = _Error;
alias _Outgoing(T) = CopyTypeQualifiers!(T, _OutgoingImpl!(Unqual!T));

enum _keyword(_: _Protocol) = "protocol";
enum _keyword(_: _Error)    = "error";

public class Parser: IProtocolParser {
    enum version_ = 0;

    alias parse = IProtocolParser.parse;

    override cmds.Command parse(string cmd, const Json args) const {
        if (cmd == "protocol")
            return _deserialize!(cmds.Protocol, _Protocol)(args);
        return cmds.Command(cmds.Error("invalidCommand", cmd, "Unknown command"));
    }

    override void stringify(ref Appender!(char[ ]) sink, const cmds.Command cmd) const {
        import sumtype;
        import utils;

        import sumtype;

        cmd.match!(
            (x) {
                alias Schema = _Outgoing!(typeof(x));
                sink._serialize!(Schema, _keyword!(Unqual!Schema))(x);
            },
            // Outgoing messages, unsupported by the currently used protocol, are simply ignored.
            _ => nothing,
        );
    }
}

@system unittest {
    import communication.protocols.test;

    mixin _setUp!Parser;
    () @safe {
        expectError(q{{"cmd": "nop"}}, "invalidCommand");
        expectError(q{{"cmd": "protocol"}}, "invalidStructure");
        expectError(q{{"cmd": "protocol", "args": null}}, "invalidStructure");
        expectError(q{{"cmd": "protocol", "args": { }}}, "invalidStructure");
        expectError(q{{"cmd": "protocol", "args": {"version": null}}}, "invalidStructure");
        expectError(q{{"cmd": "protocol", "args": {"version": "1"}}}, "invalidStructure");
        expect(q{{"cmd": "protocol", "args": {"version": 0}}}, cmds.Protocol(0));
        expect(q{{"cmd": "protocol", "args": {"version": 1}}}, cmds.Protocol(1));
        expect(q{{"cmd": "protocol", "args": {"version": -1}}}, cmds.Protocol(-1)); // Should pass.
    }();
}
