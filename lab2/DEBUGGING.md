# Lab 2 — debugging

Lab 1's advice still applies. This file is about the thing Lab 2 adds: there
are three nodes now, and the interesting bugs are never inside one of them.

## Starting with the debugger attached

```bash
cd lab2
docker compose -f docker-compose.yml -f docker-compose.debug.yml up --build -d
```

Each node gets its own debugger port:

| Node | Port | VS Code configuration |
|---|---|---|
| kvnode1 | 5011 | **Lab 2 — kvnode1** |
| kvnode2 | 5012 | **Lab 2 — kvnode2** |
| kvnode3 | 5013 | **Lab 2 — kvnode3** |

Three ports rather than one, because the bug you are chasing at CP4 lives in
the gap between two nodes: one is deferring a `LOCK` while the other waits for
the grant, and watching either one alone tells you nothing. Attach to two.
**Lab 2 — all three nodes** in the Run menu starts all three at once.

`suspend=n`, so the stack comes up whether or not you are attached yet.

## Why the overlay also changes the timeouts

Two timeouts would otherwise make debugging impossible.

`PEER_TIMEOUT_MS` goes from five seconds to an hour. Five seconds is right in
normal running — a peer that has not answered in five seconds is gone, and that
is what lets a coordinator decide to abort. But while you are stopped on a
breakpoint, the node you are inspecting answers nobody, and its peers would
abort the transaction underneath you. You would be debugging a failure you
caused by looking at it.

The proxy's read timeout goes the same way, for the reason Lab 1 explains.

Neither change is loaded by a plain `docker compose up`, so `validate.sh` still
runs against the real timeouts.

## Where to put the first breakpoint

| Symptom | Breakpoint |
|---|---|
| A peer's clock is wrong after `GOSSIP` | `LamportClock.update` — check what is being passed in, not what comes out |
| `MEMBERS` is right, `RELOAD` changes nothing | `Membership.reload` — is it being called at all, or is the list cached somewhere else? |
| Both clients get the lock, through different nodes | `LockManager.onLockRequest`, on the comparison |
| Both clients get the lock, through the same node | `LockManager.acquire`, at the top — two threads are getting past the local lock |
| A `PUT` hangs forever | `Peers.ask`, and then the other node's `onLockRequest`: somebody is deferring and never being woken |
| A `PUT` returns OK but one node is missing the value | `TwoPhase.put`, after the votes — did you reply to the client before every ACK came back? |

## Reading the log

Each node writes its prepare log to its own volume:

```bash
docker compose exec kvnode2 sh -c 'cat /var/lib/kv/*.log'
```

`P` then `C` for a committed transaction, `P` then `A` for an aborted one. A
`P` with nothing after it is a transaction that was promised and never
resolved — which is a real state, not a corrupt file, and the screencast asks
you about it.

## Starting over

The volumes survive `docker compose down`. To get three genuinely empty nodes:

```bash
docker compose down -v
```

Worth knowing which you want. `down` alone keeps the logs, which is what you
need when you are testing restart and recovery; `-v` throws them away, which is
what you need when a half-finished experiment has left a node holding a promise
it cannot resolve.
