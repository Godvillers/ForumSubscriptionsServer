module site.validation;

bool isValidDomainName(const(char)[ ] name) nothrow pure @safe {
    import std.algorithm.searching;
    import std.range;
    import std.uni;
    import std.utf;

    try
        return !name.empty && name.length <= 128 && name.all!isGraphical();
    catch (UTFException)
        return false;
    catch (Exception)
        assert(false);
}
