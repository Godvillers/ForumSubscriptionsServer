module logic.global_handler;

import logic.domain_handler;

private DomainHandler[string] _domains;

DomainHandler* registerDomain(string domain) nothrow @trusted {
    if (auto domainHandler = domain in _domains)
        return domainHandler;
    return &(_domains[domain] = createDomainHandler());
}
