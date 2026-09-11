# CS 450 — Distributed Systems (Fall 2026)

Lab handouts, starter code, and scripts for **CS 450 Distributed Systems** at Bellevue College, Fall 2026.

## Layout

```
.
├── lab0/    Toolchain and containers — docker-compose.yml, kvnode/, proxy/, client/, validate.sh
├── lab1/    Key-value store over TCP, UDP and RMI — (released Mon 10/5)
└── lab2/    Replication and two-phase commit — (released Mon 11/9)
```

Unlike a handout-plus-scaffold repo, **this repository is your working copy**. You create your own copy of it from the template at the start of the quarter and commit to it all quarter; each checkpoint is a tag you push. Lab 1 replaces the node in `lab0/kvnode/` with a key-value store you write, and Lab 2 replicates it. The Compose harness in `lab0/` is the thing every later lab and every automated checkpoint test drives, which is why you should not rename its services.

## How students use this repo

1. Post your GitHub username to the **GitHub username** assignment in Canvas.
2. From this repository, click **Use this template** → **Create a new repository**. Owner: **your own account**. Name: keep it as **`cs450-fall26-labs`**. Visibility: **Private**.
3. Add the instructor as a collaborator: your repo → **Settings** → **Collaborators** → add **`torsten-grabs-bc`**. Without this nobody can grade your work.
4. Clone your copy and work in it. Start with `lab0/README.md`.
5. Before each checkpoint deadline, run that lab's `validate.sh`. It runs exactly the checks the grader runs.
6. Tag and push (`git tag cp0 && git push origin main --tags`), then paste your repository URL and the tag name into the checkpoint assignment in Canvas.

Each lab folder contains its own `README.md` — that is the lab handout, and it is the authoritative version — plus a `validate.sh` you run before submitting. Canvas carries a short page per lab with the deadline, the points and a link here; it does not repeat the instructions, so if the two ever disagree, this repository wins.

## Notes

- Lecture decks (`.pptx`) are intentionally **not** tracked here — they live in the course materials folder and on Canvas.
- Build artifacts (`target/`, `*.class`, `*.jar`) are gitignored; compile inside the container, don't commit binaries.
- macOS `.DS_Store` files are gitignored.
- Everything builds from official public images on Docker Hub — `maven`, `eclipse-temurin`, `nginx`, `alpine` — and the Java code uses only the JDK's own HTTP server. There are no third-party dependencies to install or license.
- `lab0/docker-compose.yml` deliberately publishes **no** host port for `kvnode` and sets **no** `container_name`. Both would break `--scale`, which the checkpoint tests rely on. Don't add them.
