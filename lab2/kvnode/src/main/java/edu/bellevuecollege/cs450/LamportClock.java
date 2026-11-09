package edu.bellevuecollege.cs450;

/**
 * CS 450 Lab 2 — a Lamport clock.  TODO(cp3)
 *
 * Three rules, and you worked all three by hand in the written exercise:
 *
 *   tick()        a local event happens here: advance, then use the new value
 *   update(rx)    a message arrived carrying rx: max(own, rx) + 1
 *   now()         read the value without advancing it
 *
 * Where you call these matters more than what is inside them. A clock that
 * only ever ticks is monotone and still wrong: the ordering guarantee comes
 * from updating on every timestamped message you receive.
 *
 * Every connection gets its own thread, so every one of these methods is
 * touched concurrently. A plain `t++` is a read, an add and a write, and two
 * threads can interleave them -- the same failure as a HashMap in Lab 1, in a
 * place where the symptom is a lock that misbehaves once in fifty runs.
 */
public final class LamportClock {

    // TODO(cp3): what holds the value, and what keeps it safe from two threads?

    /** A local event: advance and return the new value. */
    public long tick() {
        // TODO(cp3)
        return 0;
    }

    /** A message arrived carrying 'received'. Returns the new value. */
    public long update(long received) {
        // TODO(cp3)
        return 0;
    }

    /** The current value, unchanged by the read. */
    public long now() {
        // TODO(cp3)
        return 0;
    }
}
