module communication.protocols;

import std.experimental.allocator.building_blocks.region;
import std.meta;
import v0 = communication.protocols.v0;
import v1 = communication.protocols.v1;
public import communication.protocols.iface;

nothrow @safe @nogc:

private alias _Parsers = AliasSeq!(v0.Parser, v1.Parser);
alias DefaultParser = _Parsers[0];
alias LatestParser  = _Parsers[$ - 1];

private immutable IProtocolParser[_Parsers.length] _parsers;

@property immutable(IProtocolParser) get(C: IProtocolParser)() pure
out (result) {
    assert((() @trusted => cast(C)result)() !is null);
}
do {
    enum i = staticIndexOf!(C, _Parsers);
    static assert(i >= 0, C.stringof ~ " is not a valid protocol parser");
    return _parsers[i];
}

immutable(IProtocolParser) get(int version_) pure {
    switch (version_) {
        foreach (i, C; _Parsers) {
            case C.version_: return _parsers[i];
        }
        default: return null;
    }
}

shared static this() @system {
    import utils;

    enum totalSize = {
        enum alignment = (void*).sizeof - 1;
        size_t result = 0;
        foreach (C; _Parsers)
            result = ((result + alignment) & ~alignment) + __traits(classInstanceSize, C);
        return result;
    }();

    __gshared InSituRegion!(totalSize, (void*).sizeof) region;
    foreach (i, C; _Parsers)
        _parsers[i] = region.make!C();
    assert(!region.available);
}
