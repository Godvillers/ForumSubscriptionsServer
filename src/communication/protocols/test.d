module communication.protocols.test;

version (unittest):

import communication.protocols.iface;

package mixin template _setUp(Parser: IProtocolParser) {
    import std.typecons: scoped;
    import vibe.data.json;
    import communication.protocols.iface;

    immutable _parser = scoped!Parser();
    immutable IProtocolParser parser = _parser;

    auto parse(string json) @safe {
        return parser.parse(parseJsonString(json));
    }

    void expect(T)(string json, T expected) @safe {
        import sumtype;
        import utils;

        parse(json).match!(
            (T found) => assert(found == expected, json),
            found     => unreachable(typeof(found).stringof),
        );
    }

    void expectError(string json, string errorKind) @safe {
        import sumtype;

        import communication.commands;
        import utils;

        parse(json).match!(
            (Error e) => assert(e.kind == errorKind, e.kind),
            x         => unreachable(typeof(x).stringof),
        );
    }
}
