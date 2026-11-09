package edu.bellevuecollege.cs450;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;

import edu.bellevuecollege.cs450.Membership.Member;

/**
 * CS 450 Lab 2 — talking to the other nodes.
 *
 * THIS CLASS IS GIVEN TO YOU, complete. It is plumbing, not the lab: opening a
 * socket, writing a line, reading a line back, and doing that to several peers
 * at once without waiting for them one after another.
 *
 * Two shapes, and the difference matters:
 *
 *   tell/tellAll   fire and forget. No reply is read. Used by PING at CP3.
 *   ask/askAll     send a line and wait for one line back, with a timeout.
 *                  Used by LOCK, PREPARE, COMMIT and ABORT.
 *
 * askAll sends to every peer in parallel and collects the answers. A peer that
 * does not answer within the timeout yields null in its slot rather than
 * hanging the caller -- which is what lets the coordinator at CP5 decide to
 * abort when somebody has gone away.
 *
 * Note that 'does not answer yet' is not a failure at CP4: a node that is
 * deferring a LOCK simply has not written its reply, and the socket stays
 * open. Choose the timeout accordingly -- it has to be longer than the longest
 * time a node may legitimately hold a lock.
 */
public final class Peers {

    private final Membership membership;
    private final int timeoutMs;
    private final ExecutorService pool = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "peer-client");
        t.setDaemon(true);
        return t;
    });

    public Peers(Membership membership, int timeoutMs) {
        this.membership = membership;
        this.timeoutMs = timeoutMs;
    }

    /** Send one line, read one line back. Null on timeout or any failure. */
    public String ask(Member peer, String line) {
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(peer.host(), peer.port()), timeoutMs);
            s.setSoTimeout(timeoutMs);
            OutputStream out = s.getOutputStream();
            out.write((line + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
            BufferedReader in = new BufferedReader(
                    new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
            String reply = in.readLine();
            return reply == null ? null : reply.trim();
        } catch (IOException e) {
            return null;
        }
    }

    /** Send one line to every peer, read nothing back. */
    public void tell(Member peer, String line) {
        pool.submit(() -> {
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress(peer.host(), peer.port()), timeoutMs);
                OutputStream out = s.getOutputStream();
                out.write((line + "\n").getBytes(StandardCharsets.UTF_8));
                out.flush();
            } catch (IOException ignored) {
                // fire and forget: a peer that is down is not this call's problem
            }
        });
    }

    public void tellAll(String line) {
        for (Member p : membership.peers()) tell(p, line);
    }

    /**
     * Ask every peer the same thing, in parallel. The returned list has one
     * entry per peer, in membership order; a slot is null when that peer did
     * not answer in time.
     */
    public List<String> askAll(String line) {
        List<Member> peers = membership.peers();
        List<Future<String>> futures = new ArrayList<>(peers.size());
        for (Member p : peers) futures.add(pool.submit(() -> ask(p, line)));

        List<String> replies = new ArrayList<>(peers.size());
        for (Future<String> f : futures) {
            try {
                replies.add(f.get(timeoutMs + 500L, TimeUnit.MILLISECONDS));
            } catch (Exception e) {
                f.cancel(true);
                replies.add(null);
            }
        }
        return replies;
    }
}
