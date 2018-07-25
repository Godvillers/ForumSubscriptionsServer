module utils;

/// How much time will you need to get what's going on here?
@property T[n] s(T, size_t n)(T[n] a) nothrow pure @safe @nogc {
    return a;
}

/// A "value" of type `void`. Allows writing `x => nothing` lambdas.
@property void nothing() nothrow pure @safe @nogc { }

/// "Typed `assert(false)`".
T unreachable(T = void)(const(char)[ ] msg) nothrow pure @safe @nogc {
    assert(false, msg);
}

/// ditto
@property T unreachable(T = void)() nothrow pure @safe @nogc {
    assert(false, "unreachable!" ~ T.stringof);
}

/// A `nothrow` variant of `RedBlackTree.insert`.
size_t rbTreeInsert(RedBlackTree, Stuff)(RedBlackTree tree, Stuff stuff) {
    // `RedBlackTree.check` really should throw `Error`s instead of `Exception`s...
    version (unittest) {
        import std.exception;

        return assumeWontThrow(tree.insert(stuff), "`RedBlackTree`'s invariant is violated");
    } else
        return tree.insert(stuff);
}

/// Allocate and initialize an object, throwing `OutOfMemoryError` on failure.
auto make(T, Allocator, Args...)(auto ref Allocator alloc, auto ref Args args) {
    import core.exception;
    import std.experimental.allocator: make;

    auto result = make!T(alloc, args);
    if (result is null)
        onOutOfMemoryError();
    return result;
}

void logStackTrace(string fmt, Exception e) nothrow @trusted {
    import std.encoding;
    import vibe.core.log;

    logError(fmt, e.toString().sanitize());
}
