module communication.protocols.test;

version (unittest):

import communication.protocols.iface;

package mixin template _setUp(Codec: IProtocolCodec) {
    import std.typecons: scoped;
    import vibe.data.json;
    import communication.protocols.iface;

    immutable _codec = scoped!Codec();
    immutable IProtocolCodec codec = _codec;

    auto parse(string json) @safe {
        return codec.parse(parseJsonString(json));
    }

    void expect(T)(string json) @safe {
        import sumtype;
        import utils;

        parse(json).match!(
            (T _) => nothing,
            found => unreachable(typeof(found).stringof),
        );
    }

    void expect(T)(string json, T expected) @safe {
        import sumtype;
        import utils;

        parse(json).match!(
            (T found) => assert(found == expected, json),
            found     => unreachable(typeof(found).stringof),
        );
    }
}
