module ordered_aa;

import std.traits;

private:

// Circular linked list.
struct _Node(K, V) {
    K key;
    V value;
    _Node* prev, next;

    invariant {
        assert((prev is null) == (next is null));
    }
}

void _evict(K, V)(ref _Node!(K, V) node) nothrow pure @safe @nogc
in {
    assert(node.prev !is null);
}
do {
    auto prev = node.prev, next = node.next;
    prev.next = next;
    next.prev = prev;
    // node.prev = node.next = null;
}

void _insertBefore(K, V)(_Node!(K, V)* node, _Node!(K, V)* anchor) nothrow pure @safe @nogc
in {
    assert(node !is null);
    assert(anchor !is null);
}
do {
    if (auto prev = anchor.prev) {
        node.prev = prev;
        prev.next = node;
    } else {
        // `anchor` was a sole node in the list.
        node.prev = anchor;
        anchor.next = node;
    }
    node.next = anchor;
    anchor.prev = node;
}

public struct OrderedAA(K, V) {
    private _Node!(K, V)[K] _aa;
    private _Node!(K, V)* _last;

    static if (isCopyable!V)
        this(this) {
            _aa = _aa.dup;
            if (_last !is null)
                _last = _last.key in _aa;
        }
    else
        @disable this(this);

    @property bool empty() const nothrow pure @safe @nogc {
        return _last is null;
    }

    @property size_t length() const nothrow pure @safe @nogc {
        return _aa.length;
    }

    void clear() {
        _last = null;
        _aa.clear();
    }

    ref V insert(K key, V value) {
        import std.algorithm.mutation;

        assert(key !in _aa,
            "Cannot insert a duplicate into an `OrderedAA!(" ~ K.stringof ~ ", " ~ V.stringof ~ ")`"
        );
        auto newNode = _Node!(K, V)(key, move(value)); // Here to propagate `@system`ness.
        auto node = (() @trusted => &(_aa[key] = move(newNode)))();
        if (_last !is null)
            _insertBefore(node, _last);
        _last = node;
        return node.value;
    }

    inout(V)* opBinaryRight(string op: "in")(K key) inout {
        if (auto p = key in _aa)
            return &p.value;
        return null;
    }

    ref inout(V) opIndex(K key) inout {
        return _aa[key].value;
    }

    private void _remove(ref _Node!(K, V) node) {
        if (length > 2)
            _evict(node);
        else if (length == 2) // A GC-allocated struct must not have pointers to itself.
            _last.prev = _last.next = null;
    }

    bool remove(K key) {
        if (auto node = key in _aa) {
            if (node is _last)
                _last = node.next;
            _remove(*node);
            _aa.remove(key);
            return true;
        }
        return false;
    }

    V* moveToFront(K key) {
        if (auto node = key in _aa) {
            if (node !is _last) {
                if (node !is _last.prev) {
                    _evict(*node);
                    _insertBefore(node, _last);
                }
                _last = node;
            }
            return &node.value;
        }
        return null;
    }

    @property ref inout(V) front() inout
    in {
        assert(!empty);
    }
    do {
        return _last.value;
    }

    void removeFront()
    in {
        assert(!empty);
    }
    do {
        auto node = _last;
        _last = node.next;
        _remove(*node);
        _aa.remove(node.key);
    }
}

nothrow pure @safe unittest {
    OrderedAA!(int, string) aa;
    assert(aa.insert(0, "a") == "a");
    assert(aa.front == "a");
    assert(aa.insert(1, "b") == "b");
    assert(aa.front == "b");
    const a = 0 in aa;
    const b = 1 in aa;
    assert(a !is null);
    assert(b !is null);
    assert(*a == "a");
    assert(*b == "b");
    assert(aa[1] == "b");
    assert(aa[0] == "a");
    assert(2 !in aa);
    assert(aa.moveToFront(1) is b);
    aa.removeFront();
    assert(aa.front == "a");
    aa.remove(0);
    assert(aa.empty);
}
