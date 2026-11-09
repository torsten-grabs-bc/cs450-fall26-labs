package edu.bellevuecollege.cs450;

import java.util.*;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

/**
 * CS 450 Lab 2 — a distributed lock, one per key.  TODO(cp4)
 *
 * Ricart & Agrawala, section 5.3, and the rule you wrote out by hand in Part 3
 * of the written exercise.
 *
 * The deferral is literal. A node that is not willing to grant yet simply does
 * not write its reply; the requester's socket stays open and blocks in read,
 * and the reply goes out when the lock is released. That is why the protocol
 * has no DENY -- there is nothing to say.
 */
public final class LockManager {

    /** What this node is doing about one key. */
    private static final class KeyState {
        boolean held;              // we are inside the critical region
        boolean wanted;            // we have an outstanding request
        long ts;                   // the timestamp on our own request
        final List<Condition> deferred = new ArrayList<>();

        /**
         * Given to you, and worth understanding before you start.
         *
         * Ricart & Agrawala orders NODES against each other. It says nothing
         * about two threads inside one node, and this server runs a thread per
         * connection -- so two local PUTs on the same key would both set
         * 'wanted', overwrite each other's timestamp, and both conclude they
         * hold the lock. Take this first, then run the distributed protocol.
         */
        final ReentrantLock local = new ReentrantLock(true);
    }

    private final ReentrantLock mutex = new ReentrantLock();
    private final Map<String, KeyState> keys = new HashMap<>();
    private final LamportClock clock;
    private final Peers peers;
    private final String selfId;

    public LockManager(LamportClock clock, Peers peers, String selfId) {
        this.clock = clock;
        this.peers = peers;
        this.selfId = selfId;
    }

    private KeyState state(String key) {
        return keys.computeIfAbsent(key, k -> new KeyState());
    }

    /**
     * Take the lock on a key, blocking until every peer has granted.
     * False if any peer failed to answer.  TODO(cp4)
     *
     * Shape: take the key's local lock; stamp a request with clock.tick();
     * peers.askAll("LOCK <key> <ts> <self>"); you hold it only if every reply
     * is a GRANT. Mind the failure path -- if you do not enter, the local lock
     * has to come back off or the next thread on this node waits forever.
     */
    public boolean acquire(String key) {
        // TODO(cp4)
        return false;
    }

    /** Leave the critical region and send the replies we held back.  TODO(cp4) */
    public void release(String key) {
        // TODO(cp4)
    }

    private void wakeDeferred(KeyState s) {
        for (Condition c : s.deferred) c.signalAll();
        s.deferred.clear();
    }

    /**
     * A peer wants the lock on a key. Return the line to reply with, blocking
     * for as long as the reply has to be deferred.  TODO(cp4)
     *
     * THE DECISION, and the whole of this checkpoint:
     *
     *   not interested   -> grant
     *   holding it       -> defer
     *   also want it     -> compare (ts, id) against our own request,
     *                       lexicographically. Lower wins. Theirs lower, we
     *                       grant; ours lower, we defer.
     *
     * The id is not decoration. Two concurrent requests routinely carry the
     * same timestamp, and comparing timestamps alone leaves both nodes
     * believing they have priority -- which is both of them entering, or
     * neither. Ids are unique, so the pair never ties.
     *
     * To defer: make a Condition from 'mutex', put it in s.deferred, and await
     * it. Awaiting releases the mutex, so the rest of the node keeps working.
     */
    public String onLockRequest(String key, long ts, String from) {
        // TODO(cp4): update the clock first -- this is a message arriving.
        return "GRANT " + key;
    }

    public void onRelease(String key, long ts, String from) {
        clock.update(ts);
        // Nothing else to do: the holder's own release wakes its deferred replies.
    }

    public boolean isHeld(String key) {
        mutex.lock();
        try {
            KeyState s = keys.get(key);
            return s != null && s.held;
        } finally {
            mutex.unlock();
        }
    }
}
