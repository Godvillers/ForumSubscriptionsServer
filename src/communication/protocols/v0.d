module communication.protocols.v0;

import vibe.data.json;

import communication.protocols.iface;
import communication.protocols.utils;
import cmds = communication.commands;

private struct _Protocol {
    int version_;
}

class Parser: IProtocolParser {
    enum version_ = 0;

    alias parse = IProtocolParser.parse;

    override cmds.Command parse(string cmd, const Json args) const @safe {
        if (cmd == "protocol")
            return _deserialize!(cmds.Protocol, _Protocol)(args);
        return cmds.Command(cmds.Error("invalidCommand", cmd, "Unknown command"));
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
