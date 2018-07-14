module communication.protocols.iface;

import std.array;
import vibe.data.json;
import vibe.data.serialization: optional;

import cmds = communication.commands;

private struct _Command {
    string cmd;
    @optional Json[string] args;
}

// TODO: Not just a parser any more, rename it.
interface IProtocolParser {
const /+pure+/ @safe:
    cmds.Command parse(string cmd, const Json args)
    in {
        assert(args.type == Json.Type.object);
    }

    void stringify(ref Appender!(char[ ]), const cmds.Command);

    final cmds.Command parse(const Json obj) nothrow {
        try {
            auto cmd = deserializeJson!_Command(obj);
            return parse(cmd.cmd, Json(cmd.args));
        } catch (Exception e)
            return cmds.Command(cmds.Error("invalidStructure", null, e.msg));
    }

    // Unfortunately, having to reimplement JSON stringification for arrays.
    final void stringify(ref Appender!(char[ ]) sink, const(cmds.Command)[ ] data) {
        sink ~= '[';
        foreach (cmd; data) {
            const oldLength = sink.data.length;
            stringify(sink, cmd);
            if (sink.data.length != oldLength)
                sink ~= ',';
        }
        if (sink.data[$ - 1] == ',')
            sink.data[$ - 1] = ']';
        else
            sink ~= ']';
    }
}
