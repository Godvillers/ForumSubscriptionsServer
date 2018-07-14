module communication.protocols.utils;

import vibe.data.json;
import cmds = communication.commands;

package @safe:

private string _genInitializer(Src)(string src) nothrow pure {
    import std.traits;

    string result;
    foreach (field; FieldNameTuple!Src) {
        result ~= field;
        result ~= ':';
        result ~= src;
        result ~= '.';
        result ~= field;
        result ~= ',';
    }
    return result;
}

private Dest _copyFields(Dest, Src)(ref Src src) {
    mixin(`Dest result = { `~_genInitializer!Src(`src`)~` };`);
    return result;
}

cmds.Command _deserialize(T, Schema)(const Json json) {
    auto parsed = deserializeJson!Schema(json);
    return cmds.Command(parsed._copyFields!T());
}

struct _Tagged(T) {
    string cmd;
    T args;
}

auto _tagged(T)(string cmd, T args) {
    return _Tagged!T(cmd, args);
}

pure unittest {
    import std.algorithm.comparison;

    const json = serializeToJsonString(_tagged("protocol", cmds.Protocol(0)));
    assert(json.among(
        q{{"cmd":"protocol","args":{"version":0}}},
        q{{"args":{"version":0},"cmd":"protocol"}},
    ), json);
}

void _serialize(Schema, string tag, Writer, T)(ref Writer w, T obj) {
    // A unit test in `communication.protocols.v1` fails when uncommenting this.
    // Maybe a bug in the compiler?..
    // w.serializeToJson(_tagged(tag, _copyFields!Schema(obj)));
    w.put(`{"cmd":"` ~ tag ~ `","args":`);
    w.serializeToJson(_copyFields!Schema(obj));
    w.put('}');
}
