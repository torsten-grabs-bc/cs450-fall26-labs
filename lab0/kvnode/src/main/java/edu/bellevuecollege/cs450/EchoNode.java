package edu.bellevuecollege.cs450;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

/**
 * CS 450 Lab 0 — a deliberately trivial node.
 *
 * It answers three routes and nothing else:
 *
 *   GET /whoami   the node's identity, one line, no punctuation
 *   GET /health   the literal string "ok"
 *   GET /         a short human-readable status page
 *
 * Every node reports the container hostname it is running in, which is how you
 * can tell replicas apart when several are behind the proxy. Nothing here is
 * distributed yet: each node keeps its own request counter in memory and knows
 * nothing about any other node. Making these nodes cooperate is Lab 1 and Lab 2.
 *
 * There are no third-party dependencies. The HTTP server is the one built into
 * the JDK, so this compiles with nothing but a JDK and a Maven compiler plugin.
 */
public final class EchoNode {

    private static final AtomicLong REQUESTS = new AtomicLong();
    private static final String NODE_ID = resolveNodeId();
    private static final Instant STARTED = Instant.now();

    public static void main(String[] args) throws IOException {
        int port = readPort();

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        // A small thread pool rather than the default single-threaded executor:
        // you will need concurrency in Lab 1, so the shape is here from the start.
        server.setExecutor(Executors.newFixedThreadPool(8));

        server.createContext("/whoami", exchange -> respond(exchange, 200, NODE_ID + "\n"));
        server.createContext("/health", exchange -> respond(exchange, 200, "ok\n"));
        server.createContext("/", EchoNode::status);

        server.start();
        System.out.println("kvnode " + NODE_ID + " listening on port " + port);
    }

    private static void status(HttpExchange exchange) throws IOException {
        long n = REQUESTS.get();
        String body = """
                CS 450 Lab 0 node
                node        : %s
                requests    : %d
                started     : %s
                now         : %s

                Try /whoami and /health. Scale this service up and watch the
                node line change between requests.
                """.formatted(NODE_ID, n, STARTED, Instant.now());
        respond(exchange, 200, body);
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        REQUESTS.incrementAndGet();
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "text/plain; charset=utf-8");
        // Identify the responding node in a header too, so tooling does not have
        // to parse the body to find out who answered.
        exchange.getResponseHeaders().add("X-Node-Id", NODE_ID);
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static int readPort() {
        String configured = System.getenv("NODE_PORT");
        if (configured == null || configured.isBlank()) {
            return 8080;
        }
        try {
            return Integer.parseInt(configured.trim());
        } catch (NumberFormatException e) {
            System.err.println("NODE_PORT is not a number: " + configured + " — falling back to 8080");
            return 8080;
        }
    }

    /**
     * Inside a container the hostname is the short container ID, which is
     * different for every replica. That is exactly the identity we want.
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

    private EchoNode() {
    }
}
