module logic.global_handler;

import logic.domain_handler;

private DomainHandler[string] _domains;

DomainHandler* registerDomain(string domain) nothrow @trusted {
    static uint id;
    if (auto domainHandler = domain in _domains)
        return domainHandler;
    return &(_domains[domain] = DomainHandler(id++));
}
