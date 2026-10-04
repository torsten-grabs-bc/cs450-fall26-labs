package edu.bellevuecollege.cs450;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

/**
 * CS 450 Lab 1 — the node.
 *
 * Two front doors onto one Store:
 *
 *   port 8080  HTTP. The Lab 0 routes still work, and the REST resources are
 *              new. Published through the proxy, so these requests are spread
 *              across replicas.
 *   port 9090  the line-based protocol. Not published. See TcpServer.
 *
 * Both reach the same Store instance, created once here. That is deliberate:
 * if the two protocols could ever disagree about what is stored, you would
 * have built two databases that happen to share a process.
 *
 * No third-party dependencies, same as Lab 0. The HTTP server is the one in
 * the JDK.
 */
public final class KvNode {

    private static final String NODE_ID = resolveNodeId();

    public static void main(String[] args) throws IOException {
        Store store = new Store();

        int kvPort = readPort("KV_PORT", 9090);
        Thread tcp = new Thread(new TcpServer(kvPort, store, NODE_ID), "tcp-listener");
        tcp.setDaemon(false);
        tcp.start();

        int httpPort = readPort("NODE_PORT", 8080);
        HttpServer server = HttpServer.create(new InetSocketAddress(httpPort), 0);
        server.setExecutor(Executors.newFixedThreadPool(8));

        // --- Lab 0 routes. The harness and the graders still use these. ---
        server.createContext("/whoami", ex -> respond(ex, 200, NODE_ID + "\n"));
        server.createContext("/health", ex -> respond(ex, 200, "ok\n"));

        // --- Lab 1 REST resources. See the handout. ---
        server.createContext("/kv", ex -> kv(ex, store));
        server.createContext("/stats", ex -> stats(ex, store));

        server.start();
        System.out.println("kvnode " + NODE_ID + " listening for HTTP on port " + httpPort);
    }

    /**
     * Everything under /kv.
     *
     *   PUT    /kv/<key>   body is the value   -> 200 "OK", or 400
     *   GET    /kv/<key>                       -> 200 value, or 404
     *   DELETE /kv/<key>                       -> 200 "OK", or 404
     *   GET    /kv                             -> 200, one key per line
     *   anything else on these paths           -> 405
     *
     * Note that one handler serves both the collection (/kv) and the items
     * (/kv/<key>). That is not an accident of the JDK's router -- it is what
     * "resources under a single naming scheme" means in practice. Compare the
     * TcpServer, where every operation is its own verb.
     *
     * The status code is the message. A client that has never spoken to you
     * before reads 404 and knows exactly what happened, with nothing else to
     * look up. Getting these right is part of CP2, not decoration.
     */
    private static void kv(HttpExchange exchange, Store store) throws IOException {
        // TODO(cp2): route on the method and the path, call the Store, choose
        // the status code. The key is whatever follows "/kv/".
        respond(exchange, 501, "not implemented\n");
    }

    /**
     *   GET /stats -> 200, body "keys=<n> node=<id>"
     *
     * Same text as the STATS reply over TCP, so that the two protocols cannot
     * drift apart. Any method other than GET gets 405.
     */
    private static void stats(HttpExchange exchange, Store store) throws IOException {
        // TODO(cp2)
        respond(exchange, 501, "not implemented\n");
    }

    static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "text/plain; charset=utf-8");
        exchange.getResponseHeaders().add("X-Node-Id", NODE_ID);
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static int readPort(String var, int fallback) {
        String configured = System.getenv(var);
        if (configured == null || configured.isBlank()) {
            return fallback;
        }
        try {
            return Integer.parseInt(configured.trim());
        } catch (NumberFormatException e) {
            System.err.println(var + " is not a number: " + configured + " — using " + fallback);
            return fallback;
        }
    }

    /**
     * Inside a container the hostname is the short container ID, which differs
     * for every replica. That is exactly the identity we want.
     */
    private static String resolveNodeId() {
        String fromEnv = System.getenv("NODE_ID");
        if (fromEnv != null && !fromEnv.isBlank()) {
            return fromEnv.trim();
        }
        try {
            return java.net.InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown-node";
        }
    }

    private KvNode() {
    }
}
