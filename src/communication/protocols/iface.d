module communication.protocols.iface;

import vibe.data.json;
import vibe.data.serialization: optional;

import cmds = communication.commands;

private struct _Command {
    string cmd;
    @optional Json[string] args;
}

interface IProtocolParser {
/+pure+/ @safe:
    cmds.Command parse(string cmd, const Json args) const
    in {
        assert(args.type == Json.Type.object);
    }

    final cmds.Command parse(const Json obj) const nothrow {
        try {
            auto cmd = deserializeJson!_Command(obj);
            return parse(cmd.cmd, Json(cmd.args));
        } catch (Exception e)
            return cmds.Command(cmds.Error("invalidStructure", null, e.msg));
    }
}
