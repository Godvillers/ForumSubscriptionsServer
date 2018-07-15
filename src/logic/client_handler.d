module logic.client_handler;

import std.array;
import std.typecons: Rebindable, rebindable, Ternary;

import vibe.core.sync;
import vibe.data.json;

import communication.protocols: IProtocolCodec, DefaultCodec, LatestCodec, get;
import logic.domain_handler;
import cmds = communication.commands;

@safe:

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

    this(DomainHandler* domainHandler) {
        _domainHandler = domainHandler;
        _codec = rebindable(get!DefaultCodec);
        _outBuffer = appender!(cmds.OutgoingCommand[ ]);
        _queuedTopics = appender!(const(cmds.Topic)[ ][ ]);
        _event = createManualEvent();
    }

    @disable this(this);

    ~this() {
        if (_domainHandler !is null)
            _unsubscribe();
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

    private void _unsubscribe() nothrow pure {
        foreach (id; _subs) {
            const ok = _domainHandler.topics[id].clients.remove(_getSelfAddr());
            assert(ok);
        }
    }

    private void _subscribe() nothrow pure {
        import std.datetime.systime;

        foreach (id; _subs)
            if (auto topic = id in _domainHandler.topics)
                topic.clients[_getSelfAddr()] = true;
            else
                _domainHandler.topics.insert(id, Topic(0, SysTime.init, [_getSelfAddr(): true]));
    }

    bool isSubscribedFor(int topicId) const nothrow pure @nogc
    in {
        assert(_domainHandler !is null);
    }
    do {
        const topic = topicId in _domainHandler.topics;
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
        _emit(cmds.Protocol(protocol.version_));
    }

    void handle(const cmds.ClientConfig config) nothrow pure {
        import std.algorithm;

        if (!config.subs.isNull) {
            // TODO: Respond with these subscriptions.
            _unsubscribe();
            _subs = config.subs.get[0 .. min($, 512)].dup;
            _subs.length -= _subs.sort().uniq().copy(_subs).length;
            _subscribe();
        }
        if (config.shareSubs != Ternary.unknown)
            _shareSubs = config.shareSubs == Ternary.yes;
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
        import std.datetime.systime;

        import vibe.core.log;

        bool[size_t] affectedClients;
        const threshold = Clock.currTime() + 3.minutes;
        foreach (topic; topics) {
            // Sanity check: ignore "updates" further than 3 minutes in the future.
            if (topic.timestamp >= threshold || topic.posts <= 0) {
                logWarn("Got a suspicious topic: %s", topic);
                continue;
            }
            if (auto found = _domainHandler.topics.moveToFront(topic.id)) {
                // Existing topic.
                if (topic.timestamp <= found.lastUpdated && topic.posts <= found.posts)
                    continue; // Nothing interesting.

                found.posts = topic.posts;
                found.lastUpdated = topic.timestamp;
                foreach (addr; found.clients.byKey())
                    if (addr != _getSelfAddr()) // Do not send notifications back to ourselves.
                        affectedClients[addr] = true;
            } else {
                // New topic.
                _domainHandler.topics.insert(topic.id, Topic(topic.posts, topic.timestamp));
            }
        }

        foreach (addr; affectedClients.byKey())
            (() @trusted => cast(ClientHandler*)addr)().wake(topics);
    }

    void handle(T)(const T e) nothrow pure if (is(T == cmds.UnknownCmd) || is(T == cmds.Error)) {
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
