# CS 450 — Lab 0: Toolchain and Containers

**Released:** Mon Sep 28 · **Checkpoint CP0 due:** Fri Oct 2, 11:59 pm · **10 points, pass/fail**

---

## What this lab is for

Every later lab in this course runs on the stack you set up here. Lab 1 replaces the node
with a key-value store you write; Lab 2 replicates that store across several nodes. Both
of them, and every automated checkpoint test, drive *this* Compose file.

So Lab 0 has one job: get a multi-container system building and running on your own
machine, and confirm you can scale it. There is almost no code to write. If it takes you
more than one lab session, something is wrong with your environment and you should say so
on the discussion board — an environment problem in week two is routine, the same problem
in week nine is a missed lab.

There is a second, quieter point. A single laptop can run five containers at once, which
is why you can build and test a genuinely distributed system by yourself, with no cloud
account and nothing to pay for. That is the whole reason this course has no lab groups.

---

## What you need

- **Docker** — Docker Desktop on macOS or Windows, or Docker Engine plus the Compose
  plugin on Linux. Check with `docker compose version`.
- **git**, and a GitHub account. See "Getting your repository" below.
- 8 GB of RAM and 2 CPUs minimum; 16 GB and 4 CPUs is a much better time.
- **Host port 8080 free.** The proxy publishes there, and so does every command in
  this handout and in the grader. Do not change the port mapping in
  `docker-compose.yml` — free the port instead. `./validate.sh` checks this first
  and tells you what to do.

You do **not** need Java or Maven installed locally. Everything compiles inside a
container. If you want to run the node outside Docker for debugging, you will need a
JDK 21, but that is optional.

### New to Docker?

Read these four before the Monday lab session. They are short, one idea each, and each
has a video. Together they cover everything this lab assumes:

- [What is a container?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/)
- [What is an image?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-an-image/)
- [What is a registry?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/)
- [What is Docker Compose?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-docker-compose/)

If you want one more, Docker's [multi-container applications](https://docs.docker.com/get-started/docker-concepts/running-containers/multi-container-applications/)
page covers the same ground as `docker-compose.yml` in this folder — though reading our
Compose file, which is commented throughout, will teach you more.

One warning about search results: **Play with Docker**, the browser sandbox that ranks
highly for "try Docker online", shut down on 1 March 2026. You need Docker installed
locally for this course in any case — the lab runs several containers at once and keeps
state between sessions.

---

## What is in here

```
docker-compose.yml     the harness — three services, and two deliberate omissions
kvnode/                the node. Lab 0: an echo service. Lab 1: your key-value store.
  pom.xml              a Maven build with zero third-party dependencies
  Dockerfile           multi-stage: build with Maven, ship on a JRE
  src/…/EchoNode.java  ~90 lines. Read it.
proxy/                 nginx, load-balancing across the kvnode replicas
client/                a shell with curl and a small `kv` wrapper script
validate.sh            run this before you submit
```

Everything is built from official public images on Docker Hub — `maven`,
`eclipse-temurin`, `nginx`, `alpine` — and the Java code uses only the JDK's own HTTP
server. There are no third-party libraries to license, download, or argue with.

---

## Do this

### 1. Build and start it

All commands below are run from inside `lab0/`.

```bash
docker compose up --build -d
```

The first build pulls a few hundred megabytes and compiles the node. Give it a few
minutes. Then:

```bash
curl http://localhost:8080/whoami
```

You should get a short node identifier — the container's hostname.

### 2. Scale it

```bash
docker compose up -d --scale kvnode=3
```

Now run the same curl several times:

```bash
for i in $(seq 1 10); do curl -s http://localhost:8080/whoami; done
```

**You should see more than one identifier.** Three replicas are running, and the proxy is
spreading requests across them.

All the same identifier? Check how many nodes you actually have before you suspect the
proxy:

```bash
docker compose ps
```

If you see one `kvnode` and not three, nothing is wrong with the load balancing — there
is only one node to balance across. Three things cause that:

- **You did not pass `--scale kvnode=3`.** Note that a later plain `docker compose up -d`
  scales you back down to one replica, silently. If you have come back to this after a
  `docker compose down`, run the scale command again.
- **Replicas could not start.** Check that `kvnode` has no `ports:` mapping and that
  nothing sets `container_name:` — see "Two things you must not change" below. A second
  replica cannot start if either is present.
- **They are still starting.** Give it a couple of seconds after scaling and try again.

If `docker compose ps` does show three running `kvnode` containers and you still get one
identifier, then read the comment at the top of `proxy/nginx.conf` — it explains how the
proxy finds the replicas, and the fix is already in the file, so check whether you have
changed that `proxy_pass` line.

### 3. Use the client container

```bash
docker compose exec client kv whoami
docker compose exec client kv spread 20
```

`kv spread` sends a burst of requests and counts how many landed on each node. This is
the same thing you just did with a shell loop, from inside the network rather than
outside it.

### 4. Break something on purpose

This part is not graded, and it is the part worth your time.

**Kill a node.**

```bash
docker compose ps                      # find a running kvnode container
docker kill <one of the kvnode containers>
for i in $(seq 1 10); do curl -s http://localhost:8080/whoami; done
```

Your requests keep succeeding. What changed is that one identifier has stopped appearing.
Nothing announced the death — you inferred it from the replies.

The reason it was painless is that two layers you did not write absorbed it. Docker's DNS
stopped handing out the dead container's address, and nginx retries another node when a
connection is refused. In Lab 1 and Lab 2 you are the one writing that layer, and the
failure arrives on your desk instead.

This is **partial failure**, and it is the property that makes a distributed system
different in kind from a program running in one process. There, a crash takes everything
with it and you know at once. Here, three nodes became two and the service carried on.

**Now pause one instead.**

```bash
docker pause <a still-running kvnode container>
curl http://localhost:8080/whoami           # count the seconds
```

A paused container stays registered in DNS and still completes the TCP handshake — the
kernel accepts the connection — but nothing inside ever replies. The proxy waits out its
five-second read timeout before giving up and trying somewhere else. The request succeeds,
just very late.

That is the failure worth remembering: **from the outside you cannot tell a slow node from
a dead one.** You can wait longer, and be wrong about a node that was merely busy; or give
up sooner, and be wrong about a node that was fine. There is no third option. Every
failure detector you meet later in this course is a timeout, and every one of them is
sometimes wrong. Run `docker unpause` when you have seen enough.

**Optional: cut one off from the network.**

```bash
docker network disconnect cs450_default <a running kvnode container>
```

The node is still running and still believes it is healthy. It simply cannot be reached,
and from the outside this looks exactly like the crash you started with. Nobody involved
is wrong, and nobody can tell the difference. That is a network partition, and in a real
deployment nobody types a command to cause one. Reconnect with
`docker network connect cs450_default <container>`.

Hold on to all three when the lecture reaches Chapter 1's eight false assumptions — not
because you have disproved any of them here (every packet in this lab travels over
loopback inside one machine, where the network really is reliable), but because these are
the failures those assumptions are trying to warn you about.

### 5. Shut it down

```bash
docker compose down
```

---

## Two things you must not change

Both would break scaling, and the checkpoint test scales your stack.

**Do not publish a host port for `kvnode`.** A published port binds to one port on your
machine, so the second replica cannot start. That is why `kvnode` uses `expose:` and not
`ports:`, and why the proxy is the only service reachable from your host.

**Do not set `container_name:` on anything.** A container name belongs to exactly one
container, so replica 2 collides with replica 1.

Also: **do not rename the `kvnode`, `proxy` or `client` services.** The grading scripts
address your containers by those exact names. Adding services is fine.

---

## Getting your repository

Do this once, before you start.

1. Post your GitHub username to the **GitHub username** assignment in Canvas (0 points,
   due Fri 9/25). Create a GitHub account first if you do not have one.
2. Open **https://github.com/torsten-grabs-bc/cs450-fall26-labs** and click
   **Use this template** → **Create a new repository**.
3. Owner: **your own account**. Name: leave it as **`cs450-fall26-labs`**.
   Visibility: **Private**.
4. Add the instructor as a collaborator: your repo → **Settings** → **Collaborators**
   → **Add people** → **`torsten-grabs-bc`**. There is no permission level to choose —
   GitHub gives collaborators on a personal repository write access, and offers no
   read-only option. The instructor only ever clones and reads; nothing is pushed to your
   repository. Do this straight away — work nobody can see cannot be graded.
5. Clone it and work there. This lab lives in `lab0/`.
6. From the repository root, run **`./scripts/link-upstream.sh`** before you change
   anything. One command, once. It connects your copy to the course repository so that
   Lab 1 and any fixes reach you later with `git pull upstream main`. Because your copy
   was made from a template it shares no history with the course repo, and git cannot
   merge unrelated histories cleanly once you have started working — running it now, on
   an untouched copy, is the difference between a silent success and a page of merge
   conflicts in week 6. The root `README.md` explains the mechanics if you are curious.

### Before your first commit: hide your email address

Every git commit permanently records the email address in your git config. Your repository
is private, but a lot of people make coursework public later for a portfolio — and by then
the addresses are already written into the history, where scrapers find them.

Two minutes now saves that. On GitHub, go to **Settings** → **Emails** and turn on both:

- **Keep my email addresses private**
- **Block command line pushes that expose my email** — GitHub then refuses a push whose
  latest commit carries one of your private addresses, so a slip fails loudly instead of
  leaking quietly.

That page also shows your GitHub **noreply address**, which looks like
`12345678+yourusername@users.noreply.github.com`. Use it for this repository:

```bash
cd cs450-fall26-labs
git config user.email "12345678+yourusername@users.noreply.github.com"
git config user.name  "Your Name"
```

Setting it inside the repository rather than with `--global` leaves your other projects
alone. Check it took effect after your first commit:

```bash
git log -1 --format='%an <%ae>'
```

None of this is graded. It is just a habit worth forming before you have a few hundred
commits with your personal address in them.

---

Keep the repository name as `cs450-fall26-labs`. The grading scripts find your work at
`github.com/<your-username>/cs450-fall26-labs`. If you renamed it, rename it back in
settings; nothing breaks.

---

## Submitting

Run the self-check first. It performs exactly the checks the grader performs:

```bash
./validate.sh
```

If it says CP0 would PASS:

```bash
git add -A
git commit -m "Lab 0 complete"
git tag cp0
git push origin main --tags
```

Then paste **your repository URL** and **the tag name** into the CP0 assignment in Canvas
before 11:59 pm on Friday Oct 2.

Checkpoints are pass/fail and cannot be submitted late — Canvas records a zero
automatically once the deadline passes. The Monday lab session after each checkpoint is
reserved for working through whatever did not pass, so if you are stuck, come to it.

---

## When it does not work

**`docker compose version` says command not found.** You have an old standalone
`docker-compose`. Either install a current Docker Desktop, or use `docker-compose` in
place of `docker compose` throughout — `validate.sh` handles both.

**The build fails downloading Maven plugins.** You are behind a proxy or offline. Try
again on a different network before assuming it is broken.

**`port is already allocated`.** Something else on your machine is using port 8080.
Most often it is your own lab stack, still running from an earlier step — `docker compose
down` and try again. Otherwise find the culprit and stop it:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Do **not** change the port mapping in `docker-compose.yml`. The grader addresses your
proxy on 8080, so a stack published anywhere else fails the checkpoint. If you genuinely
cannot free the port, post on the discussion board and we will sort it out.

**Every request hits the same node.** See step 2 above — check `docker compose ps` first.

**Everything is very slow.** Docker Desktop's default memory allocation is often too
small. Raise it in Settings → Resources.

Anything else: post on the Canvas discussion board. Include what you ran and what you saw.
Someone else has probably hit the same thing.
