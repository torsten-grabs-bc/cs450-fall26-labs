# CS 450 — Lab 1: A key-value store

**Released:** Mon Oct 5 · **CP1 due:** Fri Oct 16 · **CP2 and Lab 1 due:** Fri Oct 30 · both 11:59 pm

**Last updated:** Sun Oct 4 — changelog at the end.

This handout is the specification for Lab 1. The Canvas assignments carry the due
date, the points and the submission box, and send you back here for everything
else. If a date here ever disagrees with Canvas, Canvas is right.

---

## What this lab is for

In Lab 0 the node echoed its own name. Now you write something that holds state,
and you reach it over protocols you implement yourself rather than over HTTP that
somebody else wrote for you.

Three things here are harder than a hash map. The data arrives as a byte stream
with no message boundaries, so you decide where one request ends and the next
begins. Several clients are connected at once, so your map is touched by more
than one thread. And the same five operations have to work over two different
protocols, which forces you to separate what the store does from how it is
reached.

The storage itself is about twenty lines. Everything else is the lab.

---

## What you are building

| Piece | Due | We work on it |
|---|---|---|
| TCP server, five operations, one client at a time | **CP1**, Fri 10/16 | Mon 10/12 |
| The same five operations over REST | **CP2**, Fri 10/30 | Mon 10/19 |
| Server serves concurrent clients safely | **CP2**, Fri 10/30 | Mon 10/19 |
| Benchmark runs, results submitted | **CP2**, Fri 10/30 | debrief Mon 11/2 |

Read the protocol sections below once, then work to one checkpoint at a time.
Everything CP1 needs is §"The TCP protocol" and §"Checkpoint 1".

---

## What you need

Everything from Lab 0: Docker Desktop, host port 8080 free, and your repository
with the instructor added as a collaborator. Collect this lab:

```bash
git pull upstream main
```

Lab 1 lives in `lab1/` and has its own copy of the harness. Your Lab 0 work stays
where it is, untouched, as a reference.

---

## The TCP protocol

Clients connect to `kvnode` on **TCP port 9090**. One request per line, one
response per line, UTF-8, terminated by `\n`.

| Request | Response |
|---|---|
| `PUT <key> <value>` | `OK` |
| `GET <key>` | `VALUE <value>` or `NOT_FOUND` |
| `DEL <key>` | `OK` or `NOT_FOUND` |
| `KEYS` | `KEYS <k1> <k2> …`, or just `KEYS` when the store is empty |
| `STATS` | `STATS keys=<n> node=<id>` |

Anything you cannot parse gets `ERR <short reason>`. **Never close the connection
on a bad request** — reply with the error and carry on reading.

The rules:

- Commands are uppercase. `put` is an error, not a convenience.
- Keys are 1–64 characters and contain no spaces.
- Values may contain spaces but not newlines, up to 1024 bytes. The value is
  everything after the first space that follows the key.
- One connection handles many requests. The client decides when to disconnect.
- `node` in the `STATS` reply is the same identifier `/whoami` returns.

---

## The REST protocol

The same five operations, on the **existing HTTP server on port 8080** — this
time arranged as resources rather than as commands.

| Operation | Request | Success | Failure |
|---|---|---|---|
| PUT | `PUT /kv/<key>`, value in the body | `200`, body `OK` | `400` if the key is malformed |
| GET | `GET /kv/<key>` | `200`, value in the body | `404` |
| DEL | `DELETE /kv/<key>` | `200`, body `OK` | `404` |
| KEYS | `GET /kv` | `200`, one key per line | — |
| STATS | `GET /stats` | `200`, body `keys=<n> node=<id>` | — |

Any other method on a path returns `405`. Any path you do not recognise returns
`404`. Your Lab 0 endpoints stay exactly as they are — `/whoami` and `/health`
must keep working, because the harness and the graders still use them.

### Why this is REST, and the TCP protocol is not

Chapter 2 gives four properties. Check your implementation against them:

- **Resources are identified by a single naming scheme.** Every key is a URI
  under `/kv/`. 
- **All services offer the same interface.** Four methods, and they mean the same
  thing for every resource. Adding a feature does not add a verb.
- **Messages are fully self-described.** The status code says what happened. A
  client that has never spoken to you before can read `404` and know what it
  means.
- **After executing an operation, the server forgets the caller.** No session, no
  connection context. Each request stands entirely on its own.

Your TCP protocol fails the second and fourth of these, deliberately. `KEYS` and
`STATS` are *operations*, not resources — the verb set grows every time you add a
feature. And the connection persists across many requests, so there is a
conversation with state in it.

That is the difference between a resource-oriented style and a
procedure-call style, and Chapter 4 on Oct 14 — right between these two
checkpoints — is about the second one.

It also explains something you are about to see. Run `--scale kvnode=3`, `PUT` a
key over REST, then `GET` it a few times:

```bash
docker compose up -d --scale kvnode=3
curl -X PUT --data 'hello' http://localhost:8080/kv/greeting
for i in $(seq 1 6); do curl -s http://localhost:8080/kv/greeting; echo; done
```

Some of those come back `404`. That is not a bug in your code. Port 8080 goes
through the proxy, which spreads requests across replicas — and it can do that
precisely *because* REST is stateless and any node is as good as any other. Your
TCP client, by contrast, is pinned to the one node it dialled.

Every node is equally willing to answer, and only one of them has your data. Hold
on to that. It is the whole of Lab 2.

### A note on PUT and POST

The table in the Chapter 2 slides says POST creates a resource and PUT modifies
one. Here PUT does both, which is what real APIs do when **the client chooses the
key**. POST is for "create something and tell me where you put it" — the server
assigns the identifier. You already know the key, so there is nothing for the
server to assign, and `PUT /kv/greeting` means "make `/kv/greeting` hold this,
whatever it held before."

That also makes PUT idempotent: send it five times, get the same result as
sending it once. Which matters more than it sounds, and will matter a great deal
in Lab 2 when a message you are not sure arrived has to be sent again.

### One store, two front doors

Both protocols talk to **one store**. If you find yourself writing the storage
logic twice, stop and restructure: the store is one object, and each protocol is
a way of reaching it.

---

## Checkpoint 1 — Fri Oct 16

**What must work.** All five operations over TCP, for a single client at a time.
Concurrency is not tested here. HTTP is not tested here.

**Try it by hand.** Bring the stack up, then from inside the client container:

```bash
docker compose exec client nc kvnode 9090
```

Type `PUT greeting hello world`, then `GET greeting`. Get that round trip working
before you write anything else.

**Check yourself.**

```bash
cd lab1 && ./validate.sh
```

It performs the same checks the CP1 grader performs.

**Measure it before you move on.** The write-up compares your single-threaded
server against the concurrent one you build at CP2, so take the first half of
that comparison now, while the stack is already up:

```bash
cd lab1
./bench.sh --single tcp 1 500
./bench.sh --single tcp 4 500
```

`--single` says which server you are measuring, and those runs land in
`bench.single.txt`. Commit it.

The flag is checked rather than taken on trust. `bench.sh` holds one connection
open and sends a request down a second one; if the answer disagrees with your
flag, it writes nothing and tells you which flag to use. So you cannot
accidentally file CP2 numbers as CP1 ones.

If you forget this step, it is not lost — you tagged `cp1`, so you can check
that out later, rebuild, and measure it then.

Do not be surprised if four clients are no faster than one. That is the finding.

**Submit.**

```bash
./scripts/submit.sh cp1
```

`submit.sh` does not commit for you — commit first. It tags, pushes, then asks
GitHub whether the tag actually arrived, and prints the repository URL and tag
name for you to paste into the Canvas assignment.

**If it prints anything other than "Submitted", you have not submitted.**

At CP0, some students who had already done the work were initially not graded, because the tag
never left their laptop. `git push` sends your commits; it does not send tags
unless you name one — `git push origin cp1`. GitHub Desktop cannot create a tag
at all.

---

## Checkpoint 2 and Lab 1 — Fri Oct 30

Everything from CP1, plus three things.

### 1. The REST protocol

All five operations, as specified above, alongside the TCP ones. One store behind
both.

### 2. Concurrent clients

Several clients connected at the same time. A `PUT` in one is visible to a `GET`
in another, and nobody waits for anybody else to disconnect.

Break it on purpose first. This part is not graded and it is the part worth your
time:

```bash
docker compose exec -T client sh -c \
  'for i in $(seq 1 300); do echo "PUT k A$i"; done | nc kvnode 9090 >/dev/null' &
docker compose exec -T client sh -c \
  'for i in $(seq 1 300); do echo "PUT k B$i"; done | nc kvnode 9090 >/dev/null' &
wait
docker compose exec client sh -c 'echo KEYS | nc kvnode 9090'
```

`KEYS` should list `k` exactly once, and `GET k` should return something one of
the two writers actually wrote. If you see the key twice, or a value spliced from
two writes, your map is not safe under concurrent access. A plain `HashMap` is
not. Chapter 3 is about exactly this.

### 3. The benchmark

We ship it, so that everyone's numbers are comparable on Nov 2:

```bash
cd lab1
./bench.sh --multi tcp 1 500      # flag, protocol, clients, requests each
```

Run it for both protocols at 1, 4 and 16 clients — six runs, all appended to
`bench.multi.txt`. It reports throughput and round-trip latency.

You end up with two files: `bench.single.txt` from CP1 and `bench.multi.txt`
from now. The TCP rows at 1 and 4 clients appear in both, and the gap between
them is what the write-up is about.

Note that it measures **round-trip** latency, timed by one clock in the client.
Measuring how long the request took to travel *one way* would need the client and
server clocks to agree, and they do not. That is section 5.1, and it is the first
thing we will talk about at the debrief.

### Submit

```bash
cd lab1 && ./validate.sh cp2
cd .. && ./scripts/submit.sh cp2
```

`./validate.sh` with no argument checks CP1. Pass `cp2` and it also checks the
REST protocol, concurrency and the benchmark.

Then upload **one PDF** to the **Lab 1** assignment in Canvas. Put your
repository URL and the `cp2` tag on the first line of the first page. Two pages
is plenty, plus the benchmark output as an appendix. Cover four things:

- How you decided where one request ends and the next begins.
- How you made the store safe under concurrent access.
- A table of your measurements: single-threaded against multithreaded (the TCP
  rows at 1 and 4 clients, from your two result files), and TCP against REST.
- What you make of the difference. This is the part we read together on Nov 2 —
  bring questions about your own numbers.

Paste the contents of `bench.single.txt` and `bench.multi.txt` into the appendix,
so the runs behind your table are visible.

**The checkpoints are pass/fail and cannot be submitted late. The Lab 1 write-up
is graded on content, and the late policy in the syllabus applies to it.**

---

## What you must not change

Same rules as Lab 0. `kvnode`, `proxy` and `client` keep their service names. No
`ports:` mapping on `kvnode` — 9090 is exposed, not published, exactly like 8080.
No `container_name:` on anything.

And one more, specific to this lab:

**Neither protocol is yours to adjust.** The graders are clients that speak
exactly what is written above. `OK ` with a trailing space fails. `Value` instead
of `VALUE` fails. `200` where the spec says `404` fails. That is not pedantry —
it is what interoperating with code you did not write actually costs, and it is
why the rest of this course spends so much time agreeing on formats in advance.

---

## When it does not work

**`nc: command not found`.** You are on your own machine, not inside the client
container. Every command here starts with `docker compose exec client`.

**The first request works and the second one hangs.** You are reading a fixed
number of bytes, or reading until end-of-stream. Read until `\n` instead.

**Two clients, and the second never gets a reply.** You accept the connection and
then serve it on the thread that accepts. Hand each connection to its own.

**Values come back with a trailing `\r`.** Your client is sending CRLF rather than
LF. Strip it on the server — real clients will do this to you, and the grader is
not the thing that will change.

**`KEYS` lists a key twice.** Two threads inserted it at the same moment. See
CP2, part 2.

**A REST `GET` returns `404` for a key you just `PUT`.** Expected, if you are
running more than one replica. Read the end of the REST protocol section.

Anything else: post on the Canvas discussion board. Include what you ran and what
you saw. Someone else has probably hit the same thing.

---

## Changelog

This handout is the one place Lab 1 is specified, so when something here changes,
it is listed here. Run `git pull upstream main` to collect changes.

- **Sun Oct 4** — First release. CP1 asks you to benchmark your single-threaded
  server before CP2 replaces it, with `./bench.sh --single`; CP2 uses
  `--multi`. Lab 1 is submitted as one PDF rather than a file plus a text box.
