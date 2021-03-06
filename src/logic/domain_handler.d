module logic.domain_handler;

import std.container.rbtree;
import std.datetime.systime;
import std.range;

private nothrow @safe:

public struct Topic {
    private uint _publicSubscribers;
    int posts;
    SysTime lastUpdated;
    private bool[size_t] _clients; // bool[cast(size_t)ClientHandler*]

    @disable this(this);

    @property const nothrow pure @nogc {
        uint publicSubscribers() { return _publicSubscribers; }

        const(bool[size_t]) clients() { return _clients; }
    }
}

struct _TreeNode {
    uint subscribers;
    int topicId;

    int opCmp(_TreeNode rhs) const nothrow pure @nogc {
        import std.typecons;

        return tuple(rhs.subscribers, rhs.topicId).opCmp(tuple(subscribers, topicId));
    }
}

public struct DomainHandler {
nothrow:
    private {
        uint _id, _refCount;
        string _name;
        Topic[int] _aa;
        RedBlackTree!_TreeNode _tree;
    }

    invariant {
        assert(_aa.length >= _tree.length);
        assert(!_tree.length || _tree[ ].back.subscribers);
    }

    @disable this();
    @disable this(this);

    package this(uint id, string name) pure {
        _id = id;
        _name = name;
        _tree = new typeof(_tree);
    }

    package @property bool _readyForDeletion() const pure @nogc {
        return !_refCount && _aa.empty;
    }

    private void _destroyIfReady() {
        import logic.global_handler; // I know circular dependencies are bad.

        if (_readyForDeletion)
            _destroyDomain(_name);
    }

    void incRefCount() pure @nogc {
        _refCount++;
    }

    void decRefCount() {
        assert(_refCount, "Attempting to decrease reference count below zero");
        _refCount--;
        _destroyIfReady();
    }

    inout(Topic)* findTopic(int topicId) inout pure @nogc {
        return topicId in _aa;
    }

    @property auto mostPopularTopics() const pure @nogc {
        return _tree[ ];
    }

    private void _insertIntoTree(int topicId, uint subscribers) pure {
        import utils;

        const number = _tree.rbTreeInsert(_TreeNode(subscribers, topicId));
        assert(number == 1, "Could not insert a node into a `RedBlackTree!_TreeNode`");
    }

    private void _removeFromTree(int topicId, uint subscribers) pure @nogc {
        const number = _tree.removeKey(_TreeNode(subscribers, topicId));
        assert(number == 1, "Could not remove a node from a `RedBlackTree!_TreeNode`");
    }

    private static void _modifyPublicSubscribers(alias modify)(
        ref DomainHandler self, int topicId,
    ) pure {
        auto topic = self.findTopic(topicId);
        assert(topic !is null, "Attempting to modify public subscribers of a non-existent topic");
        if (topic.publicSubscribers)
            self._removeFromTree(topicId, topic.publicSubscribers);
        modify(topic);
        if (topic.publicSubscribers)
            self._insertIntoTree(topicId, topic.publicSubscribers);
    }

    void createTopic(int topicId, int posts, SysTime lastUpdated) pure {
        assert(topicId !in _aa, "Attempting to re-create an existing topic");
        _aa[topicId] = Topic(0, posts, lastUpdated);
    }

    private void _destroyTopic(int topicId) {
        version (assert) {
            const topic = topicId in _aa;
            assert(topic !is null, "Attempting to destroy a non-existent topic");
            assert(!topic.publicSubscribers);
            assert(topic.clients.empty);
            assert(_TreeNode(0, topicId) !in _tree);
        }
        _aa.remove(topicId);
        _destroyIfReady();
    }

    void incPublicSubscribers(int topicId) pure {
        _modifyPublicSubscribers!((ref topic) => topic._publicSubscribers++)(this, topicId);
    }

    void decPublicSubscribers(int topicId) pure {
        _modifyPublicSubscribers!((ref topic) {
            assert(topic.publicSubscribers, "Attempting to decrease public subscribers below zero");
            topic._publicSubscribers--;
        })(this, topicId);
    }

    void subscribe(int topicId, size_t clientHash, bool publicly) {
        if (auto topic = findTopic(topicId)) {
            assert(clientHash !in topic.clients, "Attempting to subscribe to a topic twice");
            if (topic.clients.empty)
                _unmarkAsOrphan(_id, topicId, *topic);
            topic._clients[clientHash] = true;
            if (publicly)
                incPublicSubscribers(topicId);
        } else {
            _aa[topicId] = Topic(publicly, 0, SysTime.init, [clientHash: true]);
            if (publicly)
                _insertIntoTree(topicId, 1);
        }
    }

    void unsubscribe(int topicId, size_t clientHash, bool publicly) {
        if (publicly)
            decPublicSubscribers(topicId);
        auto topic = findTopic(topicId);
        assert(topic !is null, "Attempting to unsubscribe from a non-existent topic");
        const ok = topic._clients.remove(clientHash);
        assert(ok, "Attempting to unsubscribe from a topic the client wasn't subscribed to");
        if (topic.clients.empty)
            _markAsOrphan(_id, topicId, *topic, (() @trusted => &this)());
    }
}

struct _OrphanTreeNode {
    SysTime lastUpdated;
    ulong discriminator;
    DomainHandler* domainHandler;

    int opCmp(ref const _OrphanTreeNode rhs) const nothrow pure {
        import std.typecons: tuple;

        return tuple(rhs.lastUpdated, rhs.discriminator).opCmp(tuple(lastUpdated, discriminator));
    }
}

RedBlackTree!_OrphanTreeNode _orphans; // Topics nobody is subscribed to.

static this() @system {
    import std.experimental.allocator.building_blocks.region;
    import utils;

    static InSituRegion!(__traits(classInstanceSize, typeof(_orphans)), (void*).sizeof) region;
    _orphans = region.make!(typeof(_orphans));
    assert(!region.available, "Too much memory reserved for orphaned topics tree");
}

void _markAsOrphan(uint domainId, int topicId, ref const Topic topic, DomainHandler* domainHandler)
in {
    assert(!topic.publicSubscribers);
    assert(topic.clients.empty);
    assert(domainHandler !is null);
}
do {
    import vibe.core.log;
    import utils;

    if (topic.lastUpdated == SysTime.init) {
        // We know nothing about the topic, no reason to hold it.
        domainHandler._destroyTopic(topicId);
        return;
    }

    if (_orphans.length >= 4096) {
        logWarn("%d orphaned topics; deleting the oldest ones", _orphans.length);
        auto garbage = _orphans[ ].dropExactly(2048); // Retain half of them.
        foreach (orphan; garbage)
            orphan.domainHandler._destroyTopic(cast(int)orphan.discriminator);
        _orphans.remove(garbage);
    }

    const number = _orphans.rbTreeInsert(
        _OrphanTreeNode(topic.lastUpdated, ulong(domainId) << 32 | topicId, domainHandler));
    assert(number == 1, "Attempting to mark the same topic as orphan twice");
}

void _unmarkAsOrphan(uint domainId, int topicId, ref const Topic topic)
in {
    assert(!topic.publicSubscribers);
    assert(topic.clients.empty);
}
do {
    const number = _orphans.removeKey(
        _OrphanTreeNode(topic.lastUpdated, ulong(domainId) << 32 | topicId));
    assert(number == 1, "Attempting to unmark a topic that was not an orphan");
}
