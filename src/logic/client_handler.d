module logic.client_handler;

import std.array;
import std.typecons: Rebindable, rebindable, Ternary;

import vibe.core.sync;
import vibe.data.json;

import communication.protocols: IProtocolCodec, DefaultCodec, LatestCodec, get;
import logic.domain_handler;
import cmds = communication.commands;

@safe:

private enum _gvSubsRequestLimit = 20;

class CommunicationException: Exception {
    this() nothrow pure @nogc { super("Communication exception"); }
}

struct ClientHandler {
    private {
        DomainHandler* _domainHandler;
        Rebindable!(immutable IProtocolCodec) _codec;
        Appender!(cmds.OutgoingCommand[ ]) _outBuffer;
        Appender!(const(cmds.Topic)[ ][ ]) _queuedTopics;
        LocalManualEvent _event;
        int[ ] _subs;
        bool _shareSubs;
    }

    invariant {
        assert(_domainHandler !is null);
    }

    @disable this();
    @disable this(this);

    this(DomainHandler* domainHandler)
    in {
        assert(domainHandler !is null);
    }
    do {
        _domainHandler = domainHandler;
        _codec = rebindable(get!DefaultCodec);
        _outBuffer = appender!(cmds.OutgoingCommand[ ]);
        _queuedTopics = appender!(const(cmds.Topic)[ ][ ]);
        _event = createManualEvent();
        domainHandler.incRefCount();
    }

    ~this() nothrow {
        _unsubscribe();
        _domainHandler.decRefCount();
    }

    void sleep() {
        _event.wait();
    }

    void wake(const(cmds.Topic)[ ] topics) nothrow {
        _queuedTopics ~= topics;
        _event.emit();
    }

    @property inout(const(cmds.Topic)[ ])[ ] queuedTopics() inout nothrow pure @nogc {
        return _queuedTopics.data;
    }

    void clearQueuedTopics() nothrow pure @nogc {
        _queuedTopics.clear();
    }

    private void _emit(T)(T cmd) nothrow pure {
        _outBuffer ~= cmds.OutgoingCommand(cmd);
    }

    private size_t _getSelfAddr() const nothrow pure @trusted @nogc {
        // All `ClientHandler`s are created on the stack, so using their addresses
        // as hash table keys is safe.
        return cast(size_t)&this;
    }

    private void _subscribe() nothrow {
        foreach (id; _subs)
            _domainHandler.subscribe(id, _getSelfAddr(), _shareSubs);
    }

    private void _unsubscribe() nothrow {
        foreach (id; _subs)
            _domainHandler.unsubscribe(id, _getSelfAddr(), _shareSubs);
    }

    bool isSubscribedFor(int topicId) const nothrow pure @nogc {
        const topic = _domainHandler.findTopic(topicId);
        return topic !is null && (_getSelfAddr() in topic.clients) !is null;
    }

    void handle(const cmds.Protocol protocol) pure {
        auto oldCodec = _codec;
        // BUG: An entire bulk of responses is encoded with the most recently set codec.
        _codec = rebindable(get(protocol.version_));
        if (_codec is null) {
            // An unsupported version is requested.
            _codec = oldCodec;
            _emit(cmds.Protocol(LatestCodec.version_));
            throw new CommunicationException;
        }
        _emit(protocol);
    }

    private cmds.Topic[ ] _collectSubsData() const nothrow pure
    out (result) {
        assert(result.length <= _subs.length);
    }
    do {
        import communication.serializable: SysTime;

        auto topics = minimallyInitializedArray!(cmds.Topic[ ])(_subs.length);
        size_t n;
        foreach (id; _subs) {
            const topic = _domainHandler.findTopic(id);
            assert(topic !is null, "Cannot find a topic we're subscribed to");
            if (topic.posts > 0)
                topics[n++] = cmds.Topic(id, topic.posts, SysTime(topic.lastUpdated));
        }
        return topics[0 .. n];
    }

    int[ ] chooseExtraSubs() const
    out (result) {
        assert(result.length <= _gvSubsRequestLimit);
    }
    do {
        import std.algorithm;
        import std.random: uniform;
        import std.range;
        import std.typecons: tuple;

        int[_gvSubsRequestLimit] ids = void;
        float[_gvSubsRequestLimit] weights = void;
        auto pairs = zip(ids[ ], weights[ ]);

        enum float noise = _gvSubsRequestLimit * .5f;
        const tail =
            _domainHandler.mostPopularTopics
            .until!q{!a.subscribers}
            .filter!(info => !isSubscribedFor(info.topicId))
            .take(_gvSubsRequestLimit)
            .enumerate()
            .map!(t =>
                // Slightly shuffle them.
                tuple(int(t.value.topicId), cast(float)t.index + uniform!"[]"(-noise, +noise)))
            .copy(pairs)
            .length;

        pairs[0 .. $ - tail].sort!q{a[1] < b[1]};
        return ids[0 .. $ - tail].dup;
    }

    void handle(const cmds.ClientConfig config) {
        import std.algorithm;
        import std.range;

        if (!config.subs.isNull) {
            _unsubscribe();
            _subs = null;
        }

        if (config.shareSubs != Ternary.unknown) {
            const newValue = config.shareSubs == Ternary.yes;
            if (newValue != _shareSubs) {
                if (newValue)
                    foreach (id; _subs)
                        _domainHandler.incPublicSubscribers(id);
                else
                    foreach (id; _subs)
                        _domainHandler.decPublicSubscribers(id);
                _shareSubs = newValue;
            }
        }

        if (!config.subs.isNull) {
            _subs = config.subs.get[0 .. min($, 512)].dup;
            _subs.length -= _subs.sort().uniq().copy(_subs).length;
            _subscribe();

            // Tell the client about their subscriptions known at the moment.
            auto data = _collectSubsData();
            if (!data.empty)
                _emit(cmds.Topics(data));

            // Ask the client to watch for some extra topics.
            auto extra = chooseExtraSubs();
            if (!extra.empty)
                _emit(cmds.ServerConfig(extra));
        }
    }

    void handle(const cmds.Confirm confirm)
    in {
        assert(_codec !is null);
    }
    do {
        handle(*confirm.wrapped);
        _emit(cmds.Confirmation("ok"));
    }

    void handle(const cmds.Topics topics) {
        import core.time;
        import std.algorithm.comparison;
        import std.datetime.systime;

        import vibe.core.log;

        bool[size_t] affectedClients;
        const threshold = Clock.currTime() + 3.minutes;
        foreach (topic; topics[0 .. min($, 512)]) {
            // Sanity check: ignore "updates" further than 3 minutes in the future.
            if (topic.timestamp >= threshold || topic.posts <= 0) {
                logWarn("Got a suspicious topic: %s", topic);
                continue;
            }
            if (auto found = _domainHandler.findTopic(topic.id)) {
                // Existing topic.
                if (topic.timestamp <= found.lastUpdated && topic.posts <= found.posts)
                    continue; // Nothing interesting.

                found.posts = topic.posts;
                found.lastUpdated = topic.timestamp;
                // Remember clients subscribed to this topic.
                () @trusted { // `.byKey()` was `@system` until 2.078.
                    foreach (addr; found.clients.byKey())
                        if (addr != _getSelfAddr()) // Do not send notifications back to ourselves.
                            affectedClients[addr] = true;
                }();
            } else {
                // New topic.
                _domainHandler.createTopic(topic.id, topic.posts, topic.timestamp);
            }
        }

        // Notify clients subscribed to at least one of the updated topics.
        () @trusted {
            foreach (addr; affectedClients.byKey())
                (cast(ClientHandler*)addr).wake(topics);
        }();
    }

    void handle(T)(const T e) nothrow pure
    if (is(T == cmds.UnknownCmd) || is(T == cmds.InvalidStructure)) {
        _emit(e);
    }

    void handle(const cmds.IncomingCommand cmd)
    in {
        assert(_codec !is null);
    }
    do {
        import sumtype;

        return cmd.match!(x => handle(x));
    }

    void handle(const(Json)[ ] commands)
    in {
        assert(_codec !is null);
    }
    do {
        _outBuffer.clear();
        foreach (json; commands)
            handle(_codec.parse(json));
    }

    bool serializeResponse(ref Appender!(char[ ]) sink, const(cmds.OutgoingCommand)[ ] response) {
        if (response.empty)
            return false;
        _codec.stringify(sink, response);
        return true;
    }

    bool serializeResponse(ref Appender!(char[ ]) sink) {
        return serializeResponse(sink, _outBuffer.data);
    }
}
