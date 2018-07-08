import std.stdio;

import protocols = communication.protocols;

void main() @safe {
    immutable parser = protocols.get(0);
    assert(parser !is null);
}
