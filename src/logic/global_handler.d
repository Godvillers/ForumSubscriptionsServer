module logic.global_handler;

import logic.domain_handler;

nothrow @safe:

private DomainHandler[string] _domains;

DomainHandler* registerDomain(string name) @trusted {
    static uint id;
    if (auto domainHandler = name in _domains)
        return domainHandler;
    return &(_domains[name] = DomainHandler(id++, name));
}

package void _destroyDomain(string name) {
    import vibe.core.log;

    logDiagnostic("Forgetting domain '%s'", name);
    version (assert) {
        const domainHandler = name in _domains;
        assert(domainHandler !is null, "Attempting to destroy a non-existent domain");
        assert(domainHandler._readyForDeletion, "Attempting to destroy a domain being used");
    }
    _domains.remove(name);
}
