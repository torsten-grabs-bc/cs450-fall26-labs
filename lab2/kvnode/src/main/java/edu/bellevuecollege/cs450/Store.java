package edu.bellevuecollege.cs450;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * CS 450 Lab 2 — the store, with a staging area.
 *
 * The Lab 1 half is already here and working. What Lab 2 adds is the middle
 * state a two-phase commit needs: a value that has been promised but not yet
 * applied, and that survives a restart.
 */
public final class Store {

    private final Map<String, String> data = new ConcurrentHashMap<>();
    private final Map<String, String[]> prepared = new ConcurrentHashMap<>(); // txid -> {key,value}
    private final Path log;

    public Store(Path log) {
        this.log = log;
        recover();
    }

    // ------------------------------------------------- Lab 1, already working

    public void put(String key, String value) { data.put(key, value); }

    public Optional<String> get(String key) { return Optional.ofNullable(data.get(key)); }

    public boolean delete(String key) { return data.remove(key) != null; }

    public List<String> keys() { return new ArrayList<>(data.keySet()); }

    public int size() { return data.size(); }

    // --------------------------------------------------------------- CP5

    /**
     * Promise to be able to commit this value later.  TODO(cp5)
     *
     * It has to be on disk before this returns. Once a participant answers
     * VOTE_COMMIT it is bound, and it must still be able to make good on that
     * after being restarted -- a promise held only in memory is a lie. Use
     * append() below, which syncs.
     */
    public void prepare(String txid, String key, String value) throws IOException {
        // TODO(cp5)
    }

    /** Apply a promise. False if we never prepared this txid.  TODO(cp5) */
    public boolean commit(String txid) throws IOException {
        // TODO(cp5)
        return false;
    }

    /** Discard a promise. Harmless if we never prepared it.  TODO(cp5) */
    public boolean abort(String txid) throws IOException {
        // TODO(cp5)
        return false;
    }

    public boolean isPrepared(String txid) { return prepared.containsKey(txid); }

    public int preparedCount() { return prepared.size(); }

    /** Append one line to the log and flush it to disk. Given to you. */
    private synchronized void append(String line) throws IOException {
        if (log == null) return;
        Files.createDirectories(log.toAbsolutePath().getParent());
        Files.writeString(log, line + "\n", StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND,
                StandardOpenOption.SYNC);
    }

    /**
     * Replay the log at startup.  TODO(cp5)
     *
     * A txid that was prepared and never resolved has to come back as still
     * prepared. That is not a loose end to tidy away -- it is exactly the
     * state a participant is supposed to be stuck in when the coordinator died
     * before telling anyone the decision, and your write-up is asked about it.
     */
    private void recover() {
        // TODO(cp5)
    }
}
