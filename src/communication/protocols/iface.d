module communication.protocols.iface;

import std.array;
import vibe.data.json;
import vibe.data.serialization: optional;

import cmds = communication.commands;

private struct _Command {
    string cmd;
    @optional Json[string] args;
}

interface IProtocolCodec {
const /+pure+/ @safe:
    cmds.IncomingCommand parse(string cmd, const Json args)
    in {
        assert(args.type == Json.Type.object);
    }

    void stringify(ref Appender!(char[ ]), const cmds.OutgoingCommand);

    final cmds.IncomingCommand parse(const Json obj) nothrow {
        try {
            auto cmd = deserializeJson!_Command(obj);
            return parse(cmd.cmd, Json(cmd.args));
        } catch (Exception e)
            return cmds.IncomingCommand(cmds.InvalidStructure(e.msg));
    }

    // Unfortunately, having to reimplement JSON stringification for arrays.
    final void stringify(ref Appender!(char[ ]) sink, const(cmds.OutgoingCommand)[ ] data) {
        sink ~= '[';
        size_t oldLength = sink.data.length;
        foreach (cmd; data) {
            stringify(sink, cmd);

            const newLength = sink.data.length;
            if (newLength != oldLength) {
                sink ~= ',';
                oldLength = newLength + 1;
            }
        }
        if (sink.data[$ - 1] == ',')
            sink.data[$ - 1] = ']';
        else
            sink ~= ']';
    }
}
