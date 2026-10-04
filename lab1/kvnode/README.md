# lab1/kvnode — what is in here

| File | What it is | Yours to change? |
|---|---|---|
| `KvNode.java` | Starts both listeners and creates the one `Store`. Holds the REST handlers. | The two `TODO(cp2)` handlers, yes. The startup wiring, no need. |
| `TcpServer.java` | The accept loop for port 9090, and one method per connection. | `handle()` is `TODO(cp1)`. The threading change is `TODO(cp2)`. |
| `Store.java` | The data. Both protocols reach it. | All of it — every method is `TODO(cp1)`. |
| `pom.xml` | Build. No dependencies, by design. | No. |
| `Dockerfile` | Multi-stage: build with Maven, ship on a JRE. | No. |

Search for `TODO(cp1)` and `TODO(cp2)` to find every gap. There are ten.

Start with `Store.java` — nothing else can work until it does — then
`TcpServer.handle()`. That pair is all of CP1.

The methods throw `UnsupportedOperationException` rather than returning
something harmless, so that a half-finished store fails loudly instead of
quietly answering `NOT_FOUND` to everything and looking like it works.
