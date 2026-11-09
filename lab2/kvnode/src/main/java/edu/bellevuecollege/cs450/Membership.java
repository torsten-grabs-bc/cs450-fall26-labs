package edu.bellevuecollege.cs450;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * CS 450 Lab 2 — the membership list.
 *
 * The file is the only source of truth. Nodes do not discover each other, do
 * not gossip membership, and do not infer peers from traffic.
 *
 * Note that 'members' is volatile and the accessors below hand back whatever
 * it points at. Replace the whole list on a reload rather than clearing and
 * refilling one, or a thread iterating during a reload sees a half-built list.
 */
public final class Membership {

    public record Member(String id, String host, int port) {}

    private final Path file;
    private final String selfId;
    private volatile List<Member> members = List.of();

    public Membership(Path file, String selfId) {
        this.file = file;
        this.selfId = selfId;
    }

    /**
     * Re-read the file and replace the list.  TODO(cp3)
     *
     * Format, one member per line:   <node-id> <host> <port>
     * Blank lines and lines starting with # are ignored.
     * Throw IOException on a line you cannot parse -- RELOAD reports it.
     *
     * This must not touch the store. A reload changes who the peers are and
     * nothing else.
     */
    public void reload() throws IOException {
        // TODO(cp3)
    }

    public List<Member> all() {
        return members;
    }

    /** Everyone but me -- the list a broadcast goes to. */
    public List<Member> peers() {
        List<Member> out = new ArrayList<>();
        for (Member m : members) if (!m.id().equals(selfId)) out.add(m);
        return out;
    }

    public List<String> ids() {
        List<String> out = new ArrayList<>();
        for (Member m : members) out.add(m.id());
        return out;
    }

    public int size() {
        return members.size();
    }

    /** For reload() to install the list it parsed. */
    protected void install(List<Member> parsed) {
        members = List.copyOf(parsed);
    }
}
