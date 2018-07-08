module communication.serializable;

import std.datetime.systime: StdSysTime = SysTime;
import std.typecons: Nullable, nullable, StdTernary = Ternary;

nothrow pure @safe @nogc:

struct Ternary {
    StdTernary data;

    alias data this;

    Nullable!bool toRepresentation() const {
        return data == StdTernary.unknown ? Nullable!bool() : nullable(data == StdTernary.yes);
    }

    static Ternary fromRepresentation(Nullable!bool value) {
        return Ternary(value.isNull ? StdTernary.unknown : StdTernary(value.get));
    }
}

struct SysTime {
    StdSysTime data;

    alias data this;

    long toRepresentation() const {
        return data.toUnixTime!long();
    }

    static SysTime fromRepresentation(long unixTime) {
        return SysTime(StdSysTime.fromUnixTime(unixTime));
    }
}
