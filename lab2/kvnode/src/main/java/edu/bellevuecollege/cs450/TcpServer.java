package edu.bellevuecollege.cs450;

import java.io.*;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * CS 450 Lab 2 — the line protocol on TCP 9090.
 *
 * Lab 1's five commands are unchanged except for PUT, which now runs a
 * transaction instead of writing straight to the map.
 *
 * The internode commands share this port and this parser deliberately: a peer
 * is just another client that happens to know more verbs.
 */
public final class TcpServer implements Runnable {

    private static final int MAX_KEY = 64;
    private static final int MAX_VALUE = 1024;

    private final int port;
    private final Store store;
    private final String nodeId;
    private final Membership membership;
    private final LamportClock clock;
    private final LockManager locks;
    private final TwoPhase txn;
    private final Peers peers;

    private final ExecutorService workers = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r);
        t.setDaemon(true);
        return t;
    });

    public TcpServer(int port, Store store, String nodeId, Membership membership,
                     LamportClock clock, LockManager locks, TwoPhase txn,
                     Peers peers) {
        this.port = port;
        this.store = store;
        this.nodeId = nodeId;
        this.membership = membership;
        this.clock = clock;
        this.locks = locks;
        this.txn = txn;
        this.peers = peers;
    }

    @Override
    public void run() {
        try (ServerSocket listener = new ServerSocket(port)) {
            System.out.println("kvnode " + nodeId + " listening for TCP on port " + port);
            while (true) {
                Socket socket = listener.accept();
                workers.submit(() -> serve(socket));
            }
        } catch (IOException e) {
            System.err.println("TCP listener on port " + port + " stopped: " + e.getMessage());
        }
    }

    private void serve(Socket socket) {
        try (socket;
             BufferedReader in = new BufferedReader(
                     new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
             OutputStream out = socket.getOutputStream()) {
            String line;
            while ((line = in.readLine()) != null) {
                String response = handle(line);
                out.write((response + "\n").getBytes(StandardCharsets.UTF_8));
                out.flush();
            }
        } catch (IOException e) {
            System.err.println("connection ended: " + e.getMessage());
        }
    }

    /** One request line in, one response line out. */
    String handle(String line) {
        if (line.endsWith("\r")) line = line.substring(0, line.length() - 1);

        int sp = line.indexOf(' ');
        String command = sp < 0 ? line : line.substring(0, sp);
        String rest = sp < 0 ? "" : line.substring(sp + 1);

        switch (command) {
            // ----------------------------------------------- Lab 1, unchanged
            case "GET" -> {
                String bad = checkKey(rest);
                if (bad != null) return bad;
                Optional<String> found = store.get(rest);
                return found.map(v -> "VALUE " + v).orElse("NOT_FOUND");
            }
            case "DEL" -> {
                String bad = checkKey(rest);
                if (bad != null) return bad;
                return store.delete(rest) ? "OK" : "NOT_FOUND";
            }
            case "KEYS" -> {
                if (!rest.isEmpty()) return "ERR KEYS takes no arguments";
                List<String> keys = store.keys();
                return keys.isEmpty() ? "KEYS" : "KEYS " + String.join(" ", keys);
            }
            case "STATS" -> {
                if (!rest.isEmpty()) return "ERR STATS takes no arguments";
                return "STATS keys=" + store.size() + " node=" + nodeId;
            }

            // -------------------------------------------- PUT, now a transaction
            case "PUT" -> {
                int s2 = rest.indexOf(' ');
                if (s2 < 0) return "ERR PUT needs a key and a value";
                String key = rest.substring(0, s2);
                String value = rest.substring(s2 + 1);
                String bad = checkKey(key);
                if (bad != null) return bad;
                if (value.getBytes(StandardCharsets.UTF_8).length > MAX_VALUE) {
                    return "ERR value is longer than " + MAX_VALUE + " bytes";
                }
                // PUT grows with the lab, one checkpoint at a time:
                //
                //   CP3  write locally, as below. Nothing is shared yet.
                //   CP4  TODO(cp4): take the lock, write locally, release it.
                //        locks.acquire(key) / store.put(...) / locks.release(key),
                //        and answer ERR if the lock could not be taken. This is
                //        what gives the lock something to do before there is a
                //        transaction to wrap.
                //   CP5  TODO(cp5): replace the whole thing with
                //            return txn.put(key, value);
                //        which takes the lock itself.
                store.put(key, value);
                return "OK";
            }

            // ------------------------------------------------------- CP3
            case "MEMBERS" -> {
                // TODO(cp3): MEMBERS <id1> <id2> ... in file order
                return "ERR not implemented";
            }
            case "RELOAD" -> {
                // TODO(cp3): re-read the file. OK, or ERR <reason> if it will
                // not parse -- and on a bad file keep serving the old list.
                return "ERR not implemented";
            }
            case "CLOCK" -> {
                // TODO(cp3): report the clock WITHOUT advancing it
                return "ERR not implemented";
            }
            case "TICK" -> {
                // TODO(cp3): one local event here, then report the new value
                return "ERR not implemented";
            }
            case "PING" -> {   // PING <ts> <node>
                // TODO(cp3): a message arrived carrying their timestamp.
                // Update this node's clock and answer
                //     PONG <our new value> <our node id>
                // The reply is a message too, so it will move the sender's
                // clock when it gets there -- which is the half of the rule
                // most people forget.
                return "ERR not implemented";
            }
            case "GOSSIP" -> {
                // TODO(cp3): one local event here; send PING <ts> <self> to
                // every peer with peers.askAll(...); fold each PONG back into
                // this node's clock. Reply  OK sent=<ts> now=<clock>
                return "ERR not implemented";
            }

            // ------------------------------------------------------- CP4
            case "LOCK" -> {
                // TODO(cp4): LOCK <key> <ts> <node> -> LockManager.onLockRequest.
                // That call may block for a long time, and that is correct:
                // the reply is deferred until this node is willing to grant.
                return "ERR not implemented";
            }
            case "RELEASE" -> {
                // TODO(cp4): LockManager.onRelease, then OK.
                return "ERR not implemented";
            }

            // ------------------------------------------------------- CP5
            case "PREPARE" -> {
                // TODO(cp5): PREPARE <txid> <key> <value>. Split into three --
                // the value is last and may contain spaces.
                return "ERR not implemented";
            }
            case "COMMIT" -> {
                // TODO(cp5)
                return "ERR not implemented";
            }
            case "ABORT" -> {
                // TODO(cp5)
                return "ERR not implemented";
            }

            default -> {
                return "ERR unknown command: " + command;
            }
        }
    }

    private static String checkKey(String key) {
        if (key.isEmpty())          return "ERR missing key";
        if (key.indexOf(' ') >= 0)  return "ERR key contains a space";
        if (key.length() > MAX_KEY) return "ERR key is longer than " + MAX_KEY + " characters";
        return null;
    }
}
