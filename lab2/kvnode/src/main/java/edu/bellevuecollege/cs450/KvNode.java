package edu.bellevuecollege.cs450;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.Executors;

/**
 * CS 450 Lab 2 — the node.
 *
 * Given to you, complete. Lab 1's wiring plus the four things Lab 2 adds: a membership list read from
 * a file, a Lamport clock, a client for talking to peers, and the lock and
 * transaction managers built on those.
 */
public final class KvNode {

    private static final int MAX_KEY = 64;
    private static final String NODE_ID = resolveNodeId();
    private static Store STORE;

    public static void main(String[] args) throws Exception {
        Path memberFile = Path.of(env("MEMBERS_FILE", "/etc/kv/members.conf"));
        Path log = Path.of(env("DATA_DIR", "/var/lib/kv")).resolve(NODE_ID + ".log");

        Store store = new Store(log);
        STORE = store;

        Membership membership = new Membership(memberFile, NODE_ID);
        try {
            membership.reload();
            System.out.println("kvnode " + NODE_ID + " members: " + membership.ids());
        } catch (IOException e) {
            System.err.println("could not read " + memberFile + ": " + e.getMessage());
        }

        LamportClock clock = new LamportClock();
        Peers peers = new Peers(membership, readInt("PEER_TIMEOUT_MS", 5000));
        LockManager locks = new LockManager(clock, peers, NODE_ID);
        TwoPhase txn = new TwoPhase(store, locks, peers, clock, NODE_ID);

        int kvPort = readInt("KV_PORT", 9090);
        Thread tcp = new Thread(
                new TcpServer(kvPort, store, NODE_ID, membership, clock, locks, txn, peers),
                "tcp-listener");
        tcp.start();

        int httpPort = readInt("NODE_PORT", 8080);
        HttpServer server = HttpServer.create(new InetSocketAddress(httpPort), 0);
        server.setExecutor(Executors.newFixedThreadPool(8));
        server.createContext("/whoami", ex -> respond(ex, 200, NODE_ID + "\n"));
        server.createContext("/health", ex -> respond(ex, 200, "ok\n"));
        server.createContext("/kv", ex -> kv(ex, store, txn));
        server.createContext("/stats", ex -> stats(ex, store));
        server.start();
        System.out.println("kvnode " + NODE_ID + " listening for HTTP on port " + httpPort);
        tcp.join();
    }

    private static void kv(HttpExchange exchange, Store store, TwoPhase txn) throws IOException {
        String path = exchange.getRequestURI().getPath();
        String method = exchange.getRequestMethod();
        String raw = path.substring("/kv".length());
        if (raw.startsWith("/")) raw = raw.substring(1);
        String key = URLDecoder.decode(raw, StandardCharsets.UTF_8);

        if (key.isEmpty()) {
            if (!"GET".equals(method)) { respond(exchange, 405, "method not allowed\n"); return; }
            List<String> keys = store.keys();
            respond(exchange, 200, keys.isEmpty() ? "" : String.join("\n", keys) + "\n");
            return;
        }
        if (key.length() > MAX_KEY || key.indexOf(' ') >= 0) {
            respond(exchange, 400, "bad key\n");
            return;
        }
        switch (method) {
            case "PUT" -> {
                String value = new String(exchange.getRequestBody().readAllBytes(),
                                          StandardCharsets.UTF_8);
                String result = txn.put(key, value);     // replicated, like TCP PUT
                if (result.startsWith("OK")) respond(exchange, 200, "OK\n");
                else respond(exchange, 503, result + "\n");
            }
            case "GET" -> {
                Optional<String> found = store.get(key);
                if (found.isPresent()) respond(exchange, 200, found.get());
                else respond(exchange, 404, "not found\n");
            }
            case "DELETE" -> respond(exchange, store.delete(key) ? 200 : 404,
                                     store.get(key).isPresent() ? "OK\n" : "not found\n");
            default -> respond(exchange, 405, "method not allowed\n");
        }
    }

    private static void stats(HttpExchange exchange, Store store) throws IOException {
        if (!"GET".equals(exchange.getRequestMethod())) {
            respond(exchange, 405, "method not allowed\n");
            return;
        }
        respond(exchange, 200, "keys=" + store.size() + " node=" + NODE_ID + "\n");
    }

    static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "text/plain; charset=utf-8");
        exchange.getResponseHeaders().add("X-Node-Id", NODE_ID);
        exchange.sendResponseHeaders(status, bytes.length == 0 ? -1 : bytes.length);
        try (OutputStream out = exchange.getResponseBody()) { out.write(bytes); }
    }

    private static String env(String var, String fallback) {
        String v = System.getenv(var);
        return (v == null || v.isBlank()) ? fallback : v.trim();
    }

    private static int readInt(String var, int fallback) {
        try { return Integer.parseInt(env(var, String.valueOf(fallback))); }
        catch (NumberFormatException e) { return fallback; }
    }

    private static String resolveNodeId() {
        String fromEnv = System.getenv("NODE_ID");
        if (fromEnv != null && !fromEnv.isBlank()) return fromEnv.trim();
        try { return java.net.InetAddress.getLocalHost().getHostName(); }
        catch (Exception e) { return "unknown-node"; }
    }

    private KvNode() {}
}
