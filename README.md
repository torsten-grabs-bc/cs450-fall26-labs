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

Labs 1 and 2 are published into this repository during the quarter, and fixes to
existing labs land here too. Your copy does not update itself. When an update is
announced in Canvas, commit whatever you are working on and pull:

```bash
git add -A && git commit -m "work in progress"
git pull upstream main
git push
```

New folders always merge cleanly. A conflict only happens if you and the course
repo changed the same file, which is rare and which git will name explicitly.

**Why the one-time link step exists.** Your repository was created from a
template, so it starts with a fresh history and shares no commits with this one.
Git merges two histories by comparing both against their common ancestor; with
no shared ancestor it cannot tell your edits from the original, and reports
*every* differing file as a conflict. `link-upstream.sh` performs that join once,
while your copy is still identical to this repo and there is nothing to
conflict — after which normal merging works for the rest of the quarter.

**If you skipped it and have already done work,** do not merge. Take the new
folder on its own instead:

```bash
git fetch upstream
git checkout upstream/main -- lab1/
```

That copies in a new lab without touching anything you have written. It
overwrites files it does land on, so use it for new folders, not for updates to
files you have edited. Ask on the discussion board if you are unsure which case
you are in.

Each lab folder contains its own `README.md` — that is the lab handout, and it is the authoritative version — plus a `validate.sh` you run before submitting. Canvas carries a short page per lab with the deadline, the points and a link here; it does not repeat the instructions, so if the two ever disagree, this repository wins.

## Notes

- Lecture decks (`.pptx`) are intentionally **not** tracked here — they live in the course materials folder and on Canvas.
- Build artifacts (`target/`, `*.class`, `*.jar`) are gitignored; compile inside the container, don't commit binaries.
- macOS `.DS_Store` files are gitignored.
- Everything builds from official public images on Docker Hub — `maven`, `eclipse-temurin`, `nginx`, `alpine` — and the Java code uses only the JDK's own HTTP server. There are no third-party dependencies to install or license.
- `lab0/docker-compose.yml` deliberately publishes **no** host port for `kvnode` and sets **no** `container_name`. Both would break `--scale`, which the checkpoint tests rely on. Don't add them.
