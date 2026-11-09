# CS 450 — Lab 2: Replication and two-phase commit

**Released:** Mon Nov 9 · **CP3 due:** Fri Nov 20 · **CP4 due:** Wed Nov 25 ·
**CP5 and Lab 2 due:** Mon Nov 30 · all 11:59 pm

**Last updated:** Mon Nov 9 — changelog at the end.

This handout is the specification for Lab 2. The Canvas assignments carry the due
date, the points and the submission box, and send you back here for everything
else. If a date here ever disagrees with Canvas, Canvas is right.

---

## What this lab is for

Lab 1 ended with a demonstration you were asked to hold on to. You ran three
replicas, wrote a key through the proxy, read it back six times, and some of
those reads returned `404`. Every node was equally willing to answer, and only
one of them had your data.

This lab is that problem.

Three things stand between you and a store that replicates. Your node has to know
who its peers are, and keep knowing when that list changes. When two clients
write the same key through two different nodes, exactly one of them has to win,
and both nodes have to agree on which. And when a write does go out to every
node, either all of them take it or none of them do — a write that lands on two
nodes out of three is worse than a write that fails.

Those are membership, mutual exclusion and atomic commit, and they are
checkpoints 3, 4 and 5.

The storage is still about twenty lines. Everything else is still the lab.

---

## What you are building

| Piece | Due | We work on it |
|---|---|---|
| Each node reads a membership list and can report its peers | **CP3**, Fri 11/20 | Mon 11/16 |
| Reloading the list without restarting the node | **CP3**, Fri 11/20 | Mon 11/16 |
| A Lamport clock, and a message that carries it between nodes | **CP3**, Fri 11/20 | Mon 11/16 |
| A distributed per-key lock — two clients race, one wins | **CP4**, Wed 11/25 | Mon 11/16 |
| `PUT` replicated to every node by two-phase commit | **CP5**, Mon 11/30 | Mon 11/23 |
| Screencast of a three-node put and a node killed mid-commit | **CP5**, Mon 11/30 | Mon 11/23 |

Read the protocol sections below once, then work to one checkpoint at a time.
Everything CP3 needs is §"The membership list" and §"Checkpoint 3".

**The checkpoints build on each other this time.** CP4's lock is held across
CP5's commit, and both need the peer list from CP3. Falling behind on CP3 is
expensive in a way that falling behind in Lab 1 was not.

**Look at the last two dates before you plan your month.** CP4 is due on a
Wednesday, not a Friday, because that Friday is Thanksgiving. CP5 follows five
days later, over the holiday weekend, and it is the hardest code in this course.
Do not wait for CP4 to be submitted before you start reading §"Checkpoint 5" —
the commit protocol wraps around the lock, so you can design both at once even
though you build them in order.

---

## How this lab is graded

Two separate things, in two separate Canvas items.

**The three checkpoints are where your code is submitted.** 10 points each,
pass/fail, on one question: does the code at that tag work? `validate.sh`
decides it and the grader runs the same checks. Tag, run
`./scripts/submit.sh`, then paste your repository URL and the tag in that
checkpoint's Canvas box. Checkpoints cannot be submitted late.

**The Lab 2 assignment is where the screencast goes, and where your code is
read.** 100 points. Thirty of them are the screencast. The other seventy are me
reading the commit at your `cp5` tag — there is nothing extra to submit for
that. Several of the things I look at are things `validate.sh` cannot test:

- whether a participant genuinely *writes* the value before it votes, rather
  than holding it in memory
- whether your lock is the algorithm, or five races that happened to pass
- where your clock is updated
- whether someone else could pick the code up

So a `cp5` tag that passes the checker can still lose marks on Lab 2. The rubric
on that assignment lists every criterion and the partial credit available. Read
it before you tag, not after.

---

## What you need

Everything from Lab 1, still working. Collect this lab:

```bash
git pull upstream main
```

Lab 2 lives in `lab2/` and starts as a copy of your Lab 1 harness with three
nodes instead of one. Your Lab 1 work stays where it is.

Bring it up and confirm you have three nodes answering:

```bash
cd lab2
docker compose up --build -d
docker compose exec client sh -c 'echo STATS | nc kvnode1 9090'
docker compose exec client sh -c 'echo STATS | nc kvnode2 9090'
docker compose exec client sh -c 'echo STATS | nc kvnode3 9090'
```

Three different `node=` values. Each node still speaks the whole Lab 1 protocol
on 9090 and the whole REST protocol through the proxy, and both must keep
working for the rest of the quarter.

---

## A note on notation

Angle brackets in this handout mark a **placeholder** — something your code
replaces with a real value. They are never characters that appear on the wire.

`PUT <key> <value>` describes the line `PUT colour green`. There are no angle
brackets in it. `GET <key>` on a key called `hot` is `GET hot`, not
`GET <hot>` — which is a request for a key whose name begins with a bracket,
and is why it comes back `NOT_FOUND`.

The same holds for `members.conf` and for every table below.

---

## The membership list

Every node reads the same file. It lives at `lab2/config/members.conf` on your
machine, and `config/` is mounted into each container at `/etc/kv`, so the node
reads it as `/etc/kv/members.conf`:

```
# one peer per line: <node-id> <host> <port>
kvnode1 kvnode1 9090
kvnode2 kvnode2 9090
kvnode3 kvnode3 9090
```

The rules:

- Blank lines and lines beginning with `#` are ignored.
- A node's own entry is in the file. It is a member of its own group.
- The node id is the same identifier `/whoami` and `STATS` already return.
- The file is the only source of truth about membership. Nodes do not discover
  each other, gossip, or infer peers from traffic.

Two new commands on the TCP protocol:

| Request | Response |
|---|---|
| `MEMBERS` | `MEMBERS <id1> <id2> …` in file order |
| `RELOAD` | `OK` after the file has been re-read, or `ERR <reason>` |

`RELOAD` re-reads the file and replaces the in-memory list. It does not restart
anything, does not drop connections, and does not disturb the store. A node that
has just reloaded answers `MEMBERS` with the new list and keeps serving requests
that were already in flight.

**Why a file.** Real systems do this with a membership service — chapter 7 — and
you are not building one. The file stands in for it, and it makes the thing you
are being graded on visible: that your node treats its peer list as something
that *changes*, rather than as a constant it read once at startup.

---

## The internode protocol

Nodes talk to each other on the same port, in the same line format, with
commands clients never send. Keep them in one place in your code; the grader
sends them directly, and so will you when you are debugging.

| Request | Response | Introduced |
|---|---|---|
| `PING <ts> <node>` | `PONG <ts> <node>` | CP3 |
| `LOCK <key> <ts> <node>` | `GRANT <key>` or nothing yet | CP4 |
| `RELEASE <key> <ts> <node>` | `OK` | CP4 |
| `PREPARE <txid> <key> <value>` | `VOTE_COMMIT <txid>` or `VOTE_ABORT <txid>` | CP5 |
| `COMMIT <txid>` | `ACK <txid>` | CP5 |
| `ABORT <txid>` | `ACK <txid>` | CP5 |

`<ts>` is a Lamport timestamp written as a **decimal integer**, no padding and
no sign — `7`, `12`, `1041`. `<node>` is the sending node's id, which is the
same string `/whoami` returns. `<txid>` is any string without spaces that is
unique to one transaction; the coordinator picks it.

The format of `<ts>` matters more than it looks, because CP4 compares two of
them. Compare them **as numbers**, not as text: as text, `"10"` sorts before
`"9"` and your lock will order requests wrongly about ten percent of the time.

Note what `LOCK` does **not** have: a "denied" reply. A node that is not willing
to grant yet says nothing and answers later. That is the algorithm, not an
oversight — see CP4.

`PING` exists for one reason: at CP3 there is no other message between nodes,
and a Lamport clock cannot be tested without one. The rule being checked is
what happens on *receipt* — `max(own, received) + 1` — and you cannot see that
from the outside unless something arrives from somewhere.

Its reply is doing a second job. A `PONG` is a message like any other, so it
moves the *sender's* clock when it gets back. That is the half of the rule
people drop: they update on requests and forget that replies count too.

`RELEASE` is in the table because the graders send it, but a correct lock may
never send it between nodes. Releasing, in Ricart & Agrawala, means writing the
replies you held back, and those go out on the connections that are still
waiting rather than as a new message.

Three more commands exist so that you and the grader can *see* the clock
instead of inferring it from behaviour:

| Request | What it does | Reply, exactly |
|---|---|---|
| `CLOCK` | reads the clock, does not advance it | `CLOCK 7 node=kvnode1` |
| `TICK` | one local event, then reads it | `CLOCK 8 node=kvnode1` |
| `GOSSIP` | one local event, then `PING` to every peer, folding each `PONG` back in | `OK sent=9 now=12` |

Those replies are literal: that is the text your node writes, with the numbers
and the id filled in.

---

## Checkpoint 3 — Fri Nov 20

**What must work.** Two things.

*Membership.* Each node reads `/etc/kv/members.conf` at startup and answers
`MEMBERS`. Editing the file and sending `RELOAD` changes what `MEMBERS` reports,
without restarting the container and without losing any stored data.

*A Lamport clock.* Each node keeps one. `TICK` advances it, `CLOCK` reports it
without advancing it, and `GOSSIP` performs one local event and then sends
`PING <ts> <node>` to every peer. A node receiving a `PING` sets its own clock
to `max(own, received) + 1` and answers `PONG <its new value> <its id>`, which
the sender folds into its own clock in turn.

**Why the clock is here rather than with the lock.** You ran this by hand in the
written exercise and the rules are three lines. What is not three lines is
calling them in the right places — and a clock updated in the wrong place still
looks healthy, because it still only ever goes up. The symptom arrives a week
later as a lock that lets two clients in once every fifty runs, by which point
you have three suspects and no way to separate them. Having it checked on its
own, now, is worth more than it looks.

Nothing is replicated yet. A `PUT` to `kvnode1` is still invisible to `kvnode2`,
and that is correct at this checkpoint.

**Try it by hand.**

```bash
cd lab2
docker compose exec client sh -c 'echo MEMBERS | nc kvnode1 9090'
```

The clock, from three freshly started nodes:

```bash
docker compose exec client sh -c 'echo TICK | nc kvnode1 9090'
docker compose exec client sh -c 'echo TICK | nc kvnode1 9090'
docker compose exec client sh -c 'echo GOSSIP | nc kvnode1 9090'
docker compose exec client sh -c 'echo CLOCK | nc kvnode2 9090'
```

From three nodes that have just started, `kvnode1` ticks to 1, then 2, then
gossips — so it sends `PING 3`.

| Check | Expect | A wrong answer means |
|---|---|---|
| `CLOCK` on kvnode2 | `CLOCK 4 node=kvnode2` | **3**: you assigned the received value instead of `max(own, received) + 1`. **1**: you ticked on receipt and threw the sender's timestamp away. |
| `CLOCK` on kvnode3 | `CLOCK 4 node=kvnode3` | same |
| the `GOSSIP` reply | `OK sent=3 now=6` | **now=3**: you ignored the `PONG`s. A reply is a message and moves your clock too — twice here, once per peer. |

Then comment out `kvnode3` in `lab2/config/members.conf` — the file on your
machine, not inside a container — and from inside the client container:

```bash
docker compose exec client sh -c 'echo RELOAD | nc kvnode1 9090'
docker compose exec client sh -c 'echo MEMBERS | nc kvnode1 9090'
```

The second list is shorter.

Two things about that are being graded, and neither is the list itself.
`kvnode1` has not restarted — check with `docker compose ps` that its uptime
did not reset. And a key you stored before the reload is still there. The
tempting shortcut is to rebuild the node's state when the file changes, and it
passes a casual look at `MEMBERS` while quietly throwing away every key the
node was holding and dropping every connection in flight. Membership changing
is an ordinary event in a running system, not a reason to start again.

**Check yourself.**

```bash
cd lab2
./validate.sh cp3
```

It performs the same checks the CP3 grader performs.

**Submit.** `validate.sh` has to pass first — a clean run, no FAIL lines. The
grader runs the same checks, so submitting a tag that does not validate is
submitting a tag that does not pass.

```bash
./scripts/submit.sh cp3
```

Then paste your repository URL and the tag in the **CP3** box in Canvas. The
script pushes the tag; Canvas is how I know to go looking for it.

Same rules as every checkpoint: commit first, and if it prints anything other
than "Submitted", you have not submitted.

---

## Checkpoint 4 — Wed Nov 25

A distributed lock, one per key, built the way §5.3 describes. **You already
worked this out by hand** — this is the written exercise from November 6, in
code.

*The written exercise said this checkpoint was due November 20. It moved to the
25th so that the November 16 session could be spent on your membership code
rather than ahead of it. Everything else that handout told you still holds.*

**What must work.** `PUT` now takes the lock on its key before writing and
releases it afterwards. It still only writes locally — replication is CP5 —
but the lock is what gives this checkpoint something to test.

Two clients, connected to two different nodes, each try to write the same key
at the same time. Exactly one holds the lock at a time. The other waits, and
proceeds when the first releases.

A `PUT` that cannot take the lock answers `ERR` rather than writing anyway.

**The algorithm.** Ricart & Agrawala, per key:

- Every node keeps a Lamport clock — the one you built and had checked at CP3.
  Every message in this section is an event at both ends.
- To take the lock on a key, a node sends `LOCK <key> <ts> <node>` to **every
  other member** and waits for a `GRANT` from all of them.
- On receiving a `LOCK` request, a node replies `GRANT` immediately if it does
  not hold the lock on that key and does not want it. If it holds the lock, it
  defers. If it wants the lock too, it compares `(ts, node)` against its own
  request. Compare the two timestamps as numbers first; only if they are equal,
  compare the two node ids as strings. Lower wins — lower means grant, higher
  means defer. (It is a pair compared in order, not a lexicographic comparison
  of the two glued together.)
- On releasing, send the deferred `GRANT`s.

**One thing the algorithm does not give you.** Ricart & Agrawala orders *nodes*
against each other. It says nothing about two threads inside one node, and your
server runs a thread per connection — so two clients writing the same key
through the **same** node will both set their request state, overwrite each
other's timestamp, and both conclude they hold the lock. The fix is a local
lock per key, taken before the distributed protocol starts. The skeleton has
one; use it.

**The tiebreak is the point.** Two requests can carry the same Lamport
timestamp — concurrent requests routinely do. Comparing timestamps alone leaves
both nodes thinking they have priority, and both enter. The node id breaks the
tie, and because ids are unique the comparison can never come out equal. That is
the rule you wrote as a function in Part 3 of the written exercise.

**Try it by hand.** Two clients racing one key from two nodes:

```bash
cd lab2
docker compose exec -T client sh -c 'echo "PUT hot fromA" | nc kvnode1 9090' &
docker compose exec -T client sh -c 'echo "PUT hot fromB" | nc kvnode2 9090' &
wait
docker compose exec client sh -c 'echo "GET hot" | nc kvnode1 9090'
docker compose exec client sh -c 'echo "GET hot" | nc kvnode2 9090'
```

Each node holds one whole value — `fromA` or `fromB` — and not a splice of the
two. The two nodes do **not** have to agree yet: a `PUT` still writes locally at
this checkpoint, so `kvnode1` holds what it was told and `kvnode2` holds what it
was told. Making them agree is CP5. What the lock buys you here is that the two
writers took turns instead of landing on top of each other.

**Check yourself.**

```bash
cd lab2
./validate.sh cp4
```

**Submit.** `validate.sh` has to pass first — a clean run, no FAIL lines. The
grader runs the same checks, so submitting a tag that does not validate is
submitting a tag that does not pass.

```bash
./scripts/submit.sh cp4
```

Then paste your repository URL and the tag in the **CP4** box in Canvas. The
script pushes the tag; Canvas is how I know to go looking for it.

---

## Checkpoint 5 and Lab 2 — Mon Nov 30

Replication, finally. A `PUT` to any node lands on all three, or on none.

**Monday November 23 is where this protocol gets taught**, and you will be
writing it in that session. Come having read this whole section and with CP4
working, because the commit wraps around the lock and there is no useful way to
build it without one. The Ch. 8 lecture two days later gives the full treatment
and the failure cases; the session gives you the algorithm and the room to ask
about your own code.

**What must work.** The node that receives a `PUT` acts as coordinator. It takes
the lock from CP4, runs two-phase commit across the members, releases the lock,
and answers the client. A `GET` on any node returns the value.

**The protocol.**

1. Coordinator takes the lock on the key.
2. Coordinator sends `PREPARE <txid> <key> <value>` to every member.
3. Each participant writes the value somewhere it can still find it if it has to
   commit, and votes `VOTE_COMMIT`. A participant that cannot take the write
   votes `VOTE_ABORT`.
4. All votes `VOTE_COMMIT` → coordinator sends `COMMIT <txid>` to everyone. Any
   `VOTE_ABORT`, or any participant that does not answer in time → `ABORT
   <txid>` to everyone.
5. Participants apply or discard, and `ACK`.
6. Coordinator releases the lock and replies `OK` to the client.

**A participant that has voted to commit may not change its mind.** Once it has
said `VOTE_COMMIT` it is bound, and it must still be able to commit after a
restart. That is the whole difficulty of 2PC and it is why step 3 says *write*,
not *remember*.

**What happens when the coordinator dies between step 4 and step 5** is the
question the chapter spends its time on, and it is where the Nov 23 session and
the Nov 25 lecture both end up.
You are not asked to solve it. You are asked to know what your implementation
does, and to say so in the write-up.

**Try it by hand.** This is the first half of the screencast, with narration:

```bash
cd lab2
docker compose up --build -d
docker compose exec client sh -c 'echo "PUT colour green" | nc kvnode1 9090'
docker compose exec client sh -c 'echo "GET colour" | nc kvnode2 9090'
docker compose exec client sh -c 'echo "GET colour" | nc kvnode3 9090'
docker compose stop kvnode3
docker compose exec client sh -c 'echo "PUT colour blue" | nc kvnode1 9090'
docker compose start kvnode3
docker compose exec client sh -c 'echo "GET colour" | nc kvnode3 9090'
```

**Check yourself.**

```bash
cd lab2
./validate.sh cp5
```

**Submit — two things.** `validate.sh` has to pass first — a clean run, no FAIL
lines. The grader runs the same checks, so submitting a tag that does not
validate is submitting a tag that does not pass.

```bash
./scripts/submit.sh cp5
```

Then paste your repository URL and the `cp5` tag in the **CP5** box in Canvas,
as at the other two checkpoints.

Then upload **one screencast** to the **Lab 2** assignment, **five minutes at
most**. There is no PDF: the screencast is the only thing you write up. It is
not, however, the only thing graded on that assignment — the commit at your
`cp5` tag is read for quality, which is the larger half of those 100 points. See
§"How this lab is graded".

Spend roughly the first two minutes showing it work: a three-node `PUT` landing
on all three, then a node killed mid-transaction and whatever your system then
does. The rest is you answering four questions out loud, with your own code on
screen:

- How does your lock decide who wins, and what happens to the loser?
- Where does a participant put the value between `VOTE_COMMIT` and `COMMIT`,
  and why does that have to survive a restart?
- What does *your* implementation do when the coordinator dies after the first
  vote and before the decision reaches everyone? Describe what actually
  happens, including if the answer is "it blocks" or "that participant is
  stuck". An honest "it hangs and here is where" is worth full marks; a
  confident wrong answer is not.
- What would you change if the group had four nodes instead of three?

One take is fine, and so is a retake. We are listening for whether you know
what your own code does, not for production polish.

**The checkpoints are pass/fail and cannot be submitted late. The Lab 2
assignment — the screencast and the quality of your code together — is graded on
content, and the late policy in the syllabus applies to it.**

---

## What you must not change

Same rules as Lab 1, and they matter more now that there are three nodes.
`kvnode1`, `kvnode2`, `kvnode3`, `proxy` and `client` keep their service names.
No `ports:` mapping on any `kvnode`. No `container_name:` on anything.

**The Lab 1 protocols still have to work, unchanged.** Every operation from CP1
and CP2 is still tested at every checkpoint in this lab. A Lab 2 that replicates
beautifully and broke `KEYS` does not pass.

**Neither protocol is yours to adjust**, including the internode commands. The
graders speak exactly what is written above.

---

## When it does not work

**`MEMBERS` lists the right nodes but `RELOAD` changes nothing.** You parsed the
file at startup into something you are not re-reading. The list has to be read
again, not cached.

**`CLOCK` on a peer reads 1 after a gossip.** You ticked when the message
arrived instead of taking `max(own, received) + 1`, so the sender's timestamp
was discarded. The clock still rises, which is why this one survives casual
testing.

**Both clients get the lock, through different nodes.** Your comparison is on
the timestamp alone and the two requests tied. Compare `(timestamp, node id)`
as a pair.

**Both clients get the lock, through the same node.** A different bug — the
distributed algorithm is not involved at all. See the note in CP4 about the
local lock.

**Neither client gets the lock, and both wait forever.** Same cause, opposite
branch: with a strict `>` and equal timestamps, each one defers to the other.
Again, the pair.

**The lock works with two nodes and deadlocks with three.** You are waiting for
grants from `members - 1` but counting the ones you received wrong, or you are
not sending a request to yourself and not accounting for it. Decide once whether
your own node is in the list, and be consistent.

**A `PUT` succeeds but one node does not have the value.** You replied to the
client before every `ACK` arrived. The client's `OK` means committed everywhere.

**Everything hangs after you kill a node.** Expected, if you have no timeout on
the vote collection. Decide what your timeout is and be ready to say what it is
on the screencast — this is one of the four questions.

**A node comes back after a restart with a transaction half-applied.** Read step
3 again.

Anything else: post on the Canvas discussion board. Include what you ran and what
you saw.

---

## Changelog

This handout is the one place Lab 2 is specified, so when something here changes,
it is listed here. Run `git pull upstream main` to collect changes.

- **Mon Nov 9** — First release.
