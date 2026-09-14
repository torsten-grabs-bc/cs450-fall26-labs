# CS 450 — Distributed Systems (Fall 2026)

Lab handouts, starter code, and scripts for **CS 450 Distributed Systems** at Bellevue College, Fall 2026.

## Layout

```
.
├── lab0/    Toolchain and containers — docker-compose.yml, kvnode/, proxy/, client/, validate.sh
├── lab1/    Key-value store over TCP, UDP and RMI — (released Mon 10/5)
├── lab2/    Replication and two-phase commit — (released Mon 11/9)
└── scripts/ link-upstream.sh — run once, right after you clone
```

Unlike a handout-plus-scaffold repo, **this repository is your working copy**. You create your own copy of it from the template at the start of the quarter and commit to it all quarter; each checkpoint is a tag you push. Lab 1 replaces the node in `lab0/kvnode/` with a key-value store you write, and Lab 2 replicates it. The Compose harness in `lab0/` is the thing every later lab and every automated checkpoint test drives, which is why you should not rename its services.

## How students use this repo

1. Post your GitHub username to the **GitHub username** assignment in Canvas.
2. From this repository, click **Use this template** → **Create a new repository**. Owner: **your own account**. Name: keep it as **`cs450-fall26-labs`**. Visibility: **Private**.
3. Add the instructor as a collaborator: your repo → **Settings** → **Collaborators** → add **`torsten-grabs-bc`**. GitHub does not offer a read-only level for collaborators on a personal repository, so this grants write access; the instructor only clones and reads. Without it nobody can grade your work.
4. Clone your copy to your machine.
5. **Run `./scripts/link-upstream.sh` right away, before you change anything.** This is a one-time step that lets you collect later labs and fixes with a single command. Doing it first costs you nothing; doing it in week 6 costs you an afternoon of merge conflicts — see *Getting updates* below.
6. Work in your copy. Start with `lab0/README.md`.
7. Before each checkpoint deadline, run that lab's `validate.sh`. It runs exactly the checks the grader runs.
8. Tag and push (`git tag cp0 && git push origin main --tags`), then paste your repository URL and the tag name into the checkpoint assignment in Canvas.

## Getting updates

Labs 1 and 2 are added to this repository during the quarter, and fixes to earlier
labs land here too. Your copy does not update itself. When an update is announced
in Canvas, save your work first, then collect it:

```bash
git add -A && git commit -m "work in progress"
git pull upstream main
git push
```

New lab folders arrive without any fuss. The only time git asks you to sort
something out is when you and the course repo changed the same file, which is
rare — and it will tell you exactly which file.

### If something looks wrong

**An editor opens, full of `#` lines.** That is vim asking you to approve a
message. Type `:wq` and press Enter. (`link-upstream.sh` turns this off, so you
should not see it.)

**`fatal: Need to specify how to reconcile divergent branches`.** Git wants to
know how to combine the two sets of changes. Use:

```bash
git pull --no-rebase upstream main
```

`link-upstream.sh` sets this for you, but the setting belongs to one folder on one
machine. If you clone your repository somewhere else, run the script again there.

**A wall of conflicts, in files you never opened.** This means the link step never
ran here. Do not try to fix the conflicts. Stop the attempt:

```bash
git merge --abort
```

If you have not started working yet, run `./scripts/link-upstream.sh` and you are
set. If you have already done work, leave your repository as it is and take the
new lab folder on its own:

```bash
git fetch upstream
git checkout upstream/main -- lab1/
```

That brings in the new folder and leaves everything you have written alone. Use it
for new folders only — it replaces any file it lands on. Ask on the discussion
board if you are not sure which case you are in.

### Why the link step exists

Your copy and this repository started life separately, even though they hold the
same files. Git works out what changed by comparing both sides to the point where
they last agreed — and until they are linked, there is no such point, so git
treats every difference as a clash, including changes only one side made.

`link-upstream.sh` joins them once, while your copy is still identical to this one
and there is nothing to clash over. After that, collecting updates is ordinary.
That is why it belongs in week 1, before you write anything.


Each lab folder contains its own `README.md` — that is the lab handout, and it is the authoritative version — plus a `validate.sh` you run before submitting. Canvas carries a short page per lab with the deadline, the points and a link here; it does not repeat the instructions, so if the two ever disagree, this repository wins.

## Notes

- Lecture decks (`.pptx`) are intentionally **not** tracked here — they live in the course materials folder and on Canvas.
- Build artifacts (`target/`, `*.class`, `*.jar`) are gitignored; compile inside the container, don't commit binaries.
- macOS `.DS_Store` files are gitignored.
- Everything builds from official public images on Docker Hub — `maven`, `eclipse-temurin`, `nginx`, `alpine` — and the Java code uses only the JDK's own HTTP server. There are no third-party dependencies to install or license.
- `lab0/docker-compose.yml` deliberately publishes **no** host port for `kvnode` and sets **no** `container_name`. Both would break `--scale`, which the checkpoint tests rely on. Don't add them.
