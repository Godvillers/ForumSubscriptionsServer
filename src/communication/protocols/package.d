module communication.protocols;

import std.meta;
import v0 = communication.protocols.v0;
import v1 = communication.protocols.v1;
public import communication.protocols.iface;

nothrow @safe @nogc:

private alias _Codecs = AliasSeq!(v0.Codec, v1.Codec);
alias DefaultCodec = _Codecs[0];
alias LatestCodec  = _Codecs[$ - 1];

private immutable IProtocolCodec[_Codecs.length] _codecs;

@property immutable(IProtocolCodec) get(C: IProtocolCodec)() pure
out (result) {
    assert((() @trusted => cast(C)result)() !is null);
}
do {
    enum i = staticIndexOf!(C, _Codecs);
    static assert(i >= 0, C.stringof ~ " is not a valid protocol codec");
    return _codecs[i];
}

immutable(IProtocolCodec) get(int version_) pure {
    switch (version_) {
        foreach (i, C; _Codecs) {
            case C.version_: return _codecs[i];
        }
        default: return null;
    }
}

shared static this() @system {
    import std.experimental.allocator.building_blocks.region;
    import utils;

    enum totalSize = {
        enum alignment = (void*).sizeof - 1;
        size_t result = 0;
        foreach (C; _Codecs)
            result = ((result + alignment) & ~alignment) + __traits(classInstanceSize, C);
        return result;
    }();

    __gshared InSituRegion!(totalSize, (void*).sizeof) region;
    foreach (i, C; _Codecs)
        _codecs[i] = region.make!C();
    assert(!region.available, "Too much memory reserved for codecs");
}
