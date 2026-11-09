package edu.bellevuecollege.cs450;

import java.io.IOException;
import java.util.List;

/**
 * CS 450 Lab 2 — two-phase commit on PUT.  TODO(cp5)
 *
 * The node that received the PUT is the coordinator. Everybody else, this node
 * included, is a participant.
 */
public final class TwoPhase {

    private final Store store;
    private final LockManager locks;
    private final Peers peers;
    private final LamportClock clock;
    private final String selfId;

    public TwoPhase(Store store, LockManager locks, Peers peers,
                    LamportClock clock, String selfId) {
        this.store = store;
        this.locks = locks;
        this.peers = peers;
        this.clock = clock;
        this.selfId = selfId;
    }

    /**
     * Coordinator. Returns the line to send back to the client.  TODO(cp5)
     *
     * The order is not arbitrary. Lock first, so two coordinators cannot run
     * overlapping transactions on one key. Then prepare, then decide, then
     * release -- releasing before the decision has reached everyone lets a
     * second write interleave with the first one's commit.
     *
     * Do not forget that this node is a participant too: its own vote and its
     * own commit are part of the transaction.
     */
    public String put(String key, String value) {
        // TODO(cp5)
        return "ERR not implemented";
    }

    // ------------------------------------------------------- participant

    /** TODO(cp5) — prepare, then vote. A prepare that fails is a VOTE_ABORT. */
    public String onPrepare(String txid, String key, String value) {
        // TODO(cp5)
        return "VOTE_ABORT " + txid;
    }

    /** TODO(cp5) */
    public String onCommit(String txid) {
        // TODO(cp5)
        return "ERR not implemented";
    }

    /** TODO(cp5) */
    public String onAbort(String txid) {
        // TODO(cp5)
        return "ERR not implemented";
    }
}
