# CS 450 — Lab 1: Debugging our Labs with Docker

**Released:** Mon Oct 12

**Last updated:** Sun Oct 11, Mon Oct 12

Distributed systems can make it a bit harder to debug your code. This document
aims to provide you with tips and tricks for debugging and troubleshooting 
when working on your labs for CS 450.

---

## Simple checks before attaching a debugger

Before you go through the steps to attach your debugger (as outlined below),
here are a few simple checks I would recommend you run first.

**1. Is the stack actually up?**

Get the list of running Docker containers 

```bash
docker compose ps
```
You should see (at least) three containers listed, all `running`. 
The proxy shows `0.0.0.0:8080->8080/tcp`. `kvnode` shows `8080/tcp, 9090/tcp` 
with no arrow — that is correct, `kvnode` is not supposed to publish a host port.

If a container is missing or restarting, then your code might have a bug. Go to step 2 then.

**2. What do the logs say?**

```bash
docker compose logs kvnode | tail -20
```

If you just started your stack, the logs should end with 
`kvnode <id> listening for TCP on port 9090`. A stack
trace here is a problem and often the root cause for issues
that only manifest further downstream.

**3. What does the validation script say?**

```bash
./validate.sh
```

Check the output of the `validate.sh` script. For 
CP1, you are aiming for `21 passed, 0 failed`.

---

## Reading the logs

Since the code is running in Docker containers, `System.out` and `System.err` do not
print to the usual places - like the Debug Console in VSCode or the terminal. Instead, they 
go into files owned by Docker. The following command attaches to the tail of the file for `kvnode`
and will show you any new log lines that Docker adds. You can change the parameter to listen
to `proxy` or `client`.

```bash
docker compose -f docker-compose.yml -f docker-compose.debug.yml logs -f kvnode
```

---

## Interactive sessions: Manually submitting requests to the system

**1. Over TCP (CP1)**
The `nc` command helps with reading and writing commands over the network. 
In distributed systems like our lab, you can use it to open an interactive session
in our stack and submit requests. As an added benefit, the connection stays open
so that you can submit other commands later. It's a great way to try out different
code paths, also when you have a debugger attached.

```bash
docker compose exec client nc kvnode 9090
```
Now you can send GET, PUT etc. at your leasure - with or without keys.

**2. Over REST (CP2)**

REST runs on port 8080, which *is* published. Given that, you can run
`curl` in your own terminal — no `docker compose exec` needed.

```bash
curl -i -X PUT --data 'hello' http://localhost:8080/kv/greeting
curl -i                       http://localhost:8080/kv/greeting
curl -i                       http://localhost:8080/kv
curl -i                       http://localhost:8080/stats
curl -i -X DELETE             http://localhost:8080/kv/greeting
curl -i                       http://localhost:8080/kv/greeting   # 404 now
```

`-i` prints the status line. Use it every time: the grader checks the status
code, not just the body. That helps finding a `200` where the spec says `404`
- which fails in the grader even when the body looks right.

The two that are easiest to forget:

```bash
curl -i -X POST http://localhost:8080/kv/greeting    # 405, not 404
curl -i http://localhost:8080/nope                   # 404
```

If a `GET` returns `404` for a key you just `PUT`, check how many replicas you
are running before you suspect your code. See "One store, two front doors" in
the handout.

## Printf debugging

You already know how to tail the logs of your proceses running in Docker. 
Before going through the steps of attaching a debugger, consider sprinkling 
`System.err.println` into your code. It survives restarts, 
is easy to add, it shows you the whole sequence rather than
one frozen moment. 

**Never debug by writing to `out`.** That stream is the protocol. A stray
`out.write(...)` goes down the socket to the client, which then sees your
debug text where a response should be. Every check fails and the reason is
invisible, because the line looks fine in your editor. Use `System.err`.

**Take per-request printing out before you benchmark.** A `println` in
`handle()` costs real time at twenty thousand requests a second, and the
Lab 1 write-up is graded on the numbers you report. Leave it in and you are
measuring your logging.

---

## Attaching a debugger — one-time setup with VSCode

The challenge with attaching the VSCode debugger in the context of our labs is
that we don't want to interfere with the automatic validation and 
benchmarking. That rules out changing `docker-compose.yml` with your debugging 
configuration: you would need to take it out again for validation or benchmarking
only to add it back later when you are coding again. Instead, you can 
create `docker-compose.debug.yml` which you instruct Docker to load when starting
your stack for a debugging session. 

Besides that, you also 

**1. `docker-compose.debug.yml`**

If you want to be able to attach the debugger in each lab, you need the  
`docker-compose.debug.yml` file in each lab directory (lab0, lab1 as of now).
If you picked up the latest changes from the course repo, it will have been
created for you. You should see it in your directories.

```yaml
services:
  kvnode:
    environment:
      JAVA_TOOL_OPTIONS: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5006"
    ports:
      - "5006:5006"
```

JAVA_TOOL_OPTIONS is an environment variable the JVM reads at startup and 
prepends to its own arguments. It’s how you add JVM flags without editing 
the Dockerfile or the entrypoint — the container still runs java -jar /app/kvnode.jar. 
The JVM announces it on stderr (Picked up JAVA_TOOL_OPTIONS: …), 
so nobody can slip flags into a JVM invisibly. -agentlib:jdwp= loads a native agent
library called jdwp — the Java Debug Wire Protocol — and hands it 
everything after the =. Your IDE then talks to that agent.


**2. `.vscode/launch.json`**

This section is for those of you who are using Microsoft VSCode. 

First, make sure you have the Extension Pack for Java installed.
Then, add the following to your `launch.json` file in `cs450-fall26-labs/.vscode` - 
or create that file and folder if they don't exist yet.


```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java", "request": "attach", "name": "Lab 1 — kvnode",
      "hostName": "localhost", "port": 5005
    },
    {
      "type": "java", "request": "attach", "name": "Lab 0 — kvnode",
      "hostName": "localhost", "port": 5006
    }
  ]
}
```

---

## Attaching a debugger and stepping through your code running in Docker

Once you have made the changes above, follow these steps to 
debug your code as it runs in a Docker container:

**1. Start Docker with both compose files**

```bash
docker compose -f docker-compose.yml -f docker-compose.debug.yml up --build -d
```

**2. Check for the Java debugger agent**

```bash
docker compose -f docker-compose.yml -f docker-compose.debug.yml logs kvnode | head -5
docker compose -f docker-compose.yml -f docker-compose.debug.yml port kvnode 5005
```

This checks that the agent is loaded and listening, that the port is published to the host, 
and that you can reach it. The first command shows the agent was loaded and is listening — you want all
four startup lines, including `Listening for transport dt_socket at address:
5005`. The second prints the host side of the port mapping, which must be
`0.0.0.0:5005`. If it prints nothing, the container was started without the
debug compose file.

**3. Attaching to the container process**

In VSCode, switch to the debugging tab and choose the correct process from the pull-down
picker (lab0 or lab1 at this point). Then hit F5.

**4. Set a breakpoint**

As you know, in VSCode, just click to the left of the code line.
The breakpoint should show in solid red. Otherwise, the attach didn't work properly.
The most likely cause for that is that your most recent edits in your Java code
did not get built. Make sure you started the Docker stack with `--build`.

**5. Trigger the breakpoint manually**

Start an interactive client for our stack:

```bash
docker compose exec client nc kvnode 9090
```
Once the client is connected, submit the command that you are trying to debug and
see if it hits your breakpoint.

**6. Detaching and cleaning up**

Since the debug configuration lives in its own separate compose file,
you can simply tear down the debugging stack and then run the normal
commands again (i.e. without `-f docker-compose.yml -f docker-compose.debug.yml`). 
No further cleanup is necessary.

```bash
docker compose down
```

---

## Timeouts and the debugger

Note that client (or your own commands) may use timeouts and fire `IOException`
inside your Java code. If you are debugging interactively, make sure you are 
removing timeouts - or using very long ones.

---

## When none of this helps

Consider posting on the discussion board, and include what you ran,
what you saw, what you expected. 

---

## Changelog

- **Sun Oct 11** - First version.
- **Mon Oct 12** - Last touches on first version.
