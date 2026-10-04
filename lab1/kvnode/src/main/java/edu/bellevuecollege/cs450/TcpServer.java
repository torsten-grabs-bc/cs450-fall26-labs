package edu.bellevuecollege.cs450;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * CS 450 Lab 1 — the line-based protocol, on TCP port 9090.
 *
 * The accept loop is written for you. What is missing is everything that
 * happens once a client is connected.
 *
 * The protocol, in full (the handout has the detail):
 *
 *   PUT <key> <value>   -> OK
 *   GET <key>           -> VALUE <value>  |  NOT_FOUND
 *   DEL <key>           -> OK             |  NOT_FOUND
 *   KEYS                -> KEYS <k1> <k2> ...   (just "KEYS" when empty)
 *   STATS               -> STATS keys=<n> node=<id>
 *   anything else       -> ERR <short reason>
 *
 * Two things are easy to get wrong and both are the point of the lab.
 *
 * TCP gives you a stream of bytes, not messages. Nothing in it marks where one
 * request stops and the next starts; that is a convention you are imposing,
 * and here the convention is the newline. A read() that returns 40 bytes may
 * hold two requests, or half of one. BufferedReader.readLine() handles that for
 * you -- but know what it is doing, because in Lab 2 you will frame messages
 * where no newline is available.
 *
 * And a bad request is not a reason to hang up. Reply ERR and keep reading. A
 * server that drops the connection every time a client fumbles is a server
 * nobody can build against.
 */
public final class TcpServer implements Runnable {

    private final int port;
    private final Store store;
    private final String nodeId;

    public TcpServer(int port, Store store, String nodeId) {
        this.port = port;
        this.store = store;
        this.nodeId = nodeId;
    }

    @Override
    public void run() {
        try (ServerSocket listener = new ServerSocket(port)) {
            System.out.println("kvnode " + nodeId + " listening for TCP on port " + port);
            while (true) {
                Socket socket = listener.accept();

                // TODO(cp2): hand this connection to its own thread.
                //
                // As written, the next accept() does not happen until this
                // client disconnects -- so a second client sits in the backlog
                // getting nothing. That is fine for CP1, which only tests one
                // client at a time, and it is the first thing CP2 checks.
                //
                // When you change it, the question stops being "does it work"
                // and becomes "what happens when two of these touch the Store
                // at the same moment". See Store.java.
                serve(socket);
            }
        } catch (IOException e) {
            System.err.println("TCP listener on port " + port + " stopped: " + e.getMessage());
        }
    }

    /**
     * One connection, start to finish. Reads requests until the client goes
     * away, answering each one.
     */
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
            // A client that vanishes mid-request is ordinary, not exceptional.
            // Log it and move on; do not take the server down with it.
            System.err.println("connection ended: " + e.getMessage());
        }
    }

    /**
     * Turn one request line into one response line.
     *
     * This is the heart of CP1. Everything above this method is plumbing.
     *
     * Things worth deciding before you write it:
     *   - where the key ends and the value begins (PUT takes both, and the
     *     value may contain spaces)
     *   - what makes a key invalid, and what you say when it is
     *   - whether a client sending CRLF gets a trailing \r stored in their
     *     value; readLine() strips the newline but not always the \r
     */
    String handle(String line) {
        // TODO(cp1): parse the line, call the Store, build the reply.
        return "ERR not implemented";
    }
}
