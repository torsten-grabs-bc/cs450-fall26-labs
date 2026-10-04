package edu.bellevuecollege.cs450;

import java.util.List;
import java.util.Optional;

/**
 * CS 450 Lab 1 — the store.
 *
 * This is the whole of your data layer, and it is the only place the data
 * lives. Both protocols reach it: the line-based TCP server on port 9090 and
 * the REST endpoints on 8080. If you ever find yourself writing storage logic
 * in one of those, it belongs here instead.
 *
 * In memory only. Nothing survives a restart, and nothing is shared with the
 * other replicas — each container has its own. Making several nodes agree on
 * what they hold is Lab 2, and it is a much harder problem than this file.
 *
 * CP1 needs this working for one caller at a time.
 * CP2 needs it correct when several threads call it at once, which is a
 * different question and not one you can answer by being careful.
 */
public final class Store {

    // TODO(cp1): choose what holds the data.
    //
    // A java.util.HashMap will pass CP1 and fail CP2, and it will fail in a way
    // that looks like a ghost: a key that appears twice, a value that is half
    // of one write and half of another, a size() that does not match what you
    // put in. Chapter 3 is about why. When you get there, the fix is one
    // import, not a redesign -- but make sure you can say what it protects you
    // against before you reach for it.

    /**
     * Store a value, replacing anything already under that key.
     */
    public void put(String key, String value) {
        // TODO(cp1)
        throw new UnsupportedOperationException("Store.put is not implemented yet");
    }

    /**
     * Fetch a value. Empty when the key is not present.
     *
     * Optional rather than null, so that "not found" is something the caller
     * has to think about rather than something they trip over. Both protocols
     * have to turn this into their own idea of absence: NOT_FOUND over TCP,
     * 404 over REST.
     */
    public Optional<String> get(String key) {
        // TODO(cp1)
        throw new UnsupportedOperationException("Store.get is not implemented yet");
    }

    /**
     * Remove a key. True if it was there, false if it was not.
     */
    public boolean delete(String key) {
        // TODO(cp1)
        throw new UnsupportedOperationException("Store.delete is not implemented yet");
    }

    /**
     * Every key currently held, in any order.
     *
     * Careful here at CP2. Handing back a view of your live data lets a caller
     * read it while another thread is writing. Hand back a copy.
     */
    public List<String> keys() {
        // TODO(cp1)
        throw new UnsupportedOperationException("Store.keys is not implemented yet");
    }

    /**
     * How many keys are held. Used by STATS and by /stats.
     */
    public int size() {
        // TODO(cp1)
        throw new UnsupportedOperationException("Store.size is not implemented yet");
    }
}
