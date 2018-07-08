module communication.protocols.utils;

import vibe.data.json;
import cmds = communication.commands;

@safe:

private Dest _copyFields(Dest, Src)(ref Src src) {
    import std.traits;

    Dest result;
    foreach (field; FieldNameTuple!Src)
        mixin(`result.`~field~` = src.`~field~`;`);
    return result;
}

package cmds.Command _deserialize(T, Schema)(const Json json) {
    auto parsed = deserializeJson!Schema(json);
    return cmds.Command(parsed._copyFields!T());
}
