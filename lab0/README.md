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

You do **not** need Java or Maven installed locally. Everything compiles inside a
container. If you want to run the node outside Docker for debugging, you will need a
JDK 21, but that is optional.

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
spreading requests across them. If every request comes back with the same identifier,
read the comment at the top of `proxy/nginx.conf` — it explains exactly why, and the fix
is already in the file.

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

```bash
docker compose ps                      # find a running kvnode container
docker kill <one of the kvnode containers>
curl http://localhost:8080/whoami      # what happens now?
```

Try it a few times. Some requests succeed and some fail, and which ones depends on timing
you do not control. Nothing in the system told you a node had died; you found out by a
request failing.

Chapter 1 lists eight assumptions that people new to distributed systems make and that
are all false. The first one is *the network is reliable*. You have just spent thirty
seconds disproving it on your own laptop. Keep that in mind when the lecture gets to it.

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
place of `docker compose` throughout — `verify.sh` handles both.

**The build fails downloading Maven plugins.** You are behind a proxy or offline. Try
again on a different network before assuming it is broken.

**`port is already allocated`.** Something else on your machine is using port 8080. Find
it with `lsof -i :8080` (macOS/Linux). Change the *left* side of the proxy's port mapping
in `docker-compose.yml` if you need to — `"8081:8080"` — and use that port everywhere,
including when you run `verify.sh` (`PROXY_PORT=8081 ./validate.sh` is not wired up
yet, so tell me if you need it).

**Every request hits the same node.** See `proxy/nginx.conf`. This is the one genuinely
interesting bug in the lab.

**Everything is very slow.** Docker Desktop's default memory allocation is often too
small. Raise it in Settings → Resources.

Anything else: post on the Canvas discussion board. Include what you ran and what you saw.
Someone else has probably hit the same thing.
