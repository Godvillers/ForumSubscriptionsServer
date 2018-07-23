module logic.domain_handler;

import std.container.rbtree;
import std.datetime.systime;
import ordered_aa;

@safe:

struct Topic {
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

private struct _TreeNode {
    uint subscribers;
    int topicId;

    int opCmp(_TreeNode rhs) const nothrow pure @nogc {
        import std.typecons;

        return tuple(rhs.subscribers, rhs.topicId).opCmp(tuple(subscribers, topicId));
    }
}

struct DomainHandler {
nothrow pure:
    private OrderedAA!(int, Topic) _topics;
    private RedBlackTree!_TreeNode _tree;

    @disable this();

    private this(RedBlackTree!_TreeNode tree) @nogc {
        _tree = tree;
    }

    inout(Topic)* findTopic(int id) inout @nogc {
        return id in _topics;
    }

    private void _insertIntoTree(int topicId, uint subscribers) {
        // `RedBlackTree.check` really should throw `Error`s instead of `Exception`s...
        version (unittest) {
            import std.exception;

            const number = assumeWontThrow(
                _tree.insert(_TreeNode(subscribers, topicId)),
                "`RedBlackTree`'s invariant is violated",
            );
        } else
            const number = _tree.insert(_TreeNode(subscribers, topicId));
        assert(number == 1, "Could not insert a node into a `RedBlackTree!_TreeNode`");
    }

    private void _removeFromTree(int topicId, uint subscribers) @nogc {
        const number = _tree.removeKey(_TreeNode(subscribers, topicId));
        assert(number == 1, "Could not remove a node from a `RedBlackTree!_TreeNode`");
    }

    private static void _modifyPublicSubscribers(alias modify)(
        ref DomainHandler self, int topicId,
    ) {
        auto topic = self.findTopic(topicId);
        assert(topic !is null, "Attempting to modify public subscribers of a non-existent topic");
        self._removeFromTree(topicId, topic.publicSubscribers);
        modify(topic);
        self._insertIntoTree(topicId, topic.publicSubscribers);
    }

    void createTopic(int topicId, int posts, SysTime lastUpdated) {
        _topics.insert(topicId, Topic(0, posts, lastUpdated));
        _insertIntoTree(topicId, 0);
    }

    void incPublicSubscribers(int topicId) {
        _modifyPublicSubscribers!((ref topic) => topic._publicSubscribers++)(this, topicId);
    }

    void decPublicSubscribers(int topicId) {
        _modifyPublicSubscribers!((ref topic) {
            assert(topic.publicSubscribers, "Attempting to decrease public subscribers below zero");
            topic._publicSubscribers--;
        })(this, topicId);
    }

    void subscribe(int topicId, size_t clientHash, bool publicly) {
        if (auto topic = findTopic(topicId)) {
            assert(clientHash !in topic.clients, "Attempting to subscribe to a topic twice");
            topic._clients[clientHash] = true;
            if (publicly)
                incPublicSubscribers(topicId);
        } else {
            _topics.insert(topicId, Topic(publicly, 0, SysTime.init, [clientHash: true]));
            _insertIntoTree(topicId, publicly);
        }
    }

    void unsubscribe(int topicId, size_t clientHash, bool publicly) {
        if (publicly)
            decPublicSubscribers(topicId);
        const ok = _topics[topicId]._clients.remove(clientHash);
        assert(ok, "Attempting to unsubscribe from a topic the client wasn't subscribed to");
    }
}

DomainHandler createDomainHandler() nothrow pure {
    return DomainHandler(new RedBlackTree!_TreeNode);
}
