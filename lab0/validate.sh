#!/usr/bin/env bash
#
# CS 450 Lab 0 -- self-check.
#
# Run this before you submit. It performs exactly the checks the CP0 grader
# performs, so if this says PASS, the checkpoint passes.
#
#   ./validate.sh
#
# It builds the stack, brings up three kvnode replicas behind the proxy, sends
# a burst of requests, and confirms that more than one node answered. Then it
# tears everything down again.
#
set -uo pipefail

REPLICAS="${REPLICAS:-3}"
REQUESTS="${REQUESTS:-15}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-90}"
SPREAD_TIMEOUT="${SPREAD_TIMEOUT:-45}"  # how long to keep trying before calling the spread bad
PROJECT="cs450-verify-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

pass=0
fail=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
info() { printf '        %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# --- 0. course-repo link (advisory, never affects PASS/FAIL) ---------------
# A repository created from the template shares no history with the course
# repository until scripts/link-upstream.sh has been run. Say so here, at CP0,
# rather than letting it surface as a wall of conflicts when Lab 1 ships.
#
# Only when a person is watching. Remotes are local configuration, not repository
# content, so a fresh clone never has an 'upstream' -- including the throwaway
# clone the grader makes. Without the [ -t 1 ] test this advisory would appear in
# every grading log for every student, which is noise that means nothing there.
if [ -t 1 ] &&
   git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 &&
   ! git -C "$ROOT" remote get-url upstream >/dev/null 2>&1; then
  printf '\n\033[33mNOTE\033[0m  This repository is not linked to the course repository yet.\n'
  printf '        Run ./scripts/link-upstream.sh from the repository root so you\n'
  printf '        can collect Lab 1 and later fixes with a single command.\n'
  printf '        It does not affect this check or your grade.\n'
fi

# --- pick a compose command ------------------------------------------------
if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  echo "Could not find 'docker compose' or 'docker-compose'." >&2
  echo "Install Docker Desktop (or Docker Engine plus the Compose plugin) and try again." >&2
  exit 2
fi

cleanup() {
  "${DC[@]}" -p "$PROJECT" down --remove-orphans --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '\033[1mCS 450 Lab 0 verification\033[0m\n'
info "project root: $ROOT"

# --- 1. structural checks --------------------------------------------------
head_ "1. Compose file"

if "${DC[@]}" config --quiet >/dev/null 2>&1; then
  ok "docker-compose.yml parses"
else
  bad "docker-compose.yml does not parse"
  "${DC[@]}" config 2>&1 | sed 's/^/        /' | head -20
  echo; echo "Stopping here -- nothing else can run."; exit 1
fi

CONFIG="$("${DC[@]}" config 2>/dev/null)"

for svc in kvnode proxy client; do
  if grep -qE "^  ${svc}:" <<<"$CONFIG"; then
    ok "service '${svc}' is defined"
  else
    bad "service '${svc}' is missing -- the grader addresses it by that exact name"
  fi
done

if grep -q "container_name" <<<"$CONFIG"; then
  bad "a service sets container_name -- that makes scaling impossible, remove it"
else
  ok "no service pins container_name"
fi

# kvnode must not publish a host port, or the second replica cannot start.
#
# This check has no external dependencies on purpose. It used to call python3,
# which is not reliably present -- macOS has no `python`, plenty of Linux setups
# have neither, and on Windows `python3` is often a Microsoft Store alias that
# exists but does nothing. Worse, the old code read ANY non-zero exit as "ports
# found", so a missing interpreter accused the student of publishing a host port
# they had never added.
#
# An awk version had the mirror-image bug: no awk meant a silent PASS on a
# compose file that really was broken. Both failure modes come from depending on
# a tool that may not be installed, so this uses bash builtins only. If the
# script is running at all, bash is present, and the check runs.
#
# $CONFIG is the `docker compose config` output captured above; the checks before
# this one already rely on its two-space service indentation.
kvnode_publishes_a_port() {
  local line in_kvnode=0
  while IFS= read -r line; do
    case "$line" in
      "  kvnode:"*)      in_kvnode=1; continue ;;
      "  "[![:space:]]*) in_kvnode=0 ;;
    esac
    if [ "$in_kvnode" = 1 ]; then
      case "$line" in
        "    ports:"*) return 0 ;;
      esac
    fi
  done <<<"$CONFIG"
  return 1
}

if kvnode_publishes_a_port; then
  bad "kvnode publishes a host port -- only one replica can bind it, so --scale fails. Remove the ports: mapping; use expose: instead"
else
  ok "kvnode publishes no host port (required for scaling)"
fi

# --- 2. port 8080 ----------------------------------------------------------
# This lab requires host port 8080. Everything downstream -- the reachability
# check below, the grader, and the commands in the handout -- addresses the
# proxy there, so a port conflict has to be reported as an instruction rather
# than surfacing as Docker's "port is already allocated" halfway through a
# multi-minute build.
# Finding what listens on a port has no portable command. lsof is on macOS, ss on
# most Linux, and Git Bash on Windows passes through Windows' netstat. Without
# this fallback every Windows student silently loses this check -- and then meets
# the same conflict later as a confusing curl: (7) or a Docker "port is already
# allocated" halfway through a build.
#
# Returns 0 = something is listening, 1 = nothing is, 2 = cannot tell.
# "Cannot tell" must never read as "free". A missing tool quietly becoming a PASS
# is the bug python3 and awk already caused in this script once each.
PORT_TOOL=""
port_8080_busy() {
  if command -v lsof >/dev/null 2>&1; then
    PORT_TOOL="lsof -nP -iTCP:8080 -sTCP:LISTEN"
    lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1
  elif command -v ss >/dev/null 2>&1; then
    PORT_TOOL="ss -ltnp | grep :8080"
    ss -ltn 2>/dev/null | grep -q ':8080[[:space:]]'
  elif command -v netstat >/dev/null 2>&1; then
    PORT_TOOL="netstat -ano | findstr :8080"
    netstat -an 2>/dev/null | grep -qE '[:.]8080[[:space:]].*LISTEN'
  else
    return 2
  fi
}

head_ "2. Port 8080"
port_8080_busy; busy=$?
if [ "$busy" -eq 2 ]; then
  info "no lsof, ss or netstat here -- cannot check whether 8080 is free"
  info "if the build below fails with \"port is already allocated\", that is why"
elif [ "$busy" -ne 0 ]; then
  ok "port 8080 is free"
# The most likely thing holding 8080 is the student's OWN stack, still running
# from step 1 of the handout. Say that plainly instead of sending them off to
# hunt a mystery process.
elif [ -n "$("${DC[@]}" -p cs450 ps -q proxy 2>/dev/null)" ]; then
  bad "port 8080 is held by your own lab stack, which is still running"
  info "this self-check starts its own copy, so shut yours down first:"
  info "    docker compose down"
  info "then run ./validate.sh again"
  exit 1
else
  bad "port 8080 is already in use on your machine"
  info "this lab requires 8080. find what is holding it with:"
  info "    $PORT_TOOL"
  info "stop that process, then run ./validate.sh again"
  info "do NOT change the port mapping in docker-compose.yml -- the grader expects 8080"
  exit 1
fi

# --- 3. build --------------------------------------------------------------
head_ "3. Build"
info "this can take a few minutes the first time"
if "${DC[@]}" -p "$PROJECT" build >/tmp/cs450-build.log 2>&1; then
  ok "all three images build"
else
  bad "build failed -- last 25 lines follow"
  tail -25 /tmp/cs450-build.log | sed 's/^/        /'
  exit 1
fi

# --- 3. bring the cluster up ----------------------------------------------
head_ "4. Start ${REPLICAS} replicas"
if "${DC[@]}" -p "$PROJECT" up -d --scale "kvnode=${REPLICAS}" >/tmp/cs450-up.log 2>&1; then
  ok "compose up --scale kvnode=${REPLICAS} succeeded"
else
  bad "compose up failed -- last 25 lines follow"
  tail -25 /tmp/cs450-up.log | sed 's/^/        /'
  exit 1
fi

running=$("${DC[@]}" -p "$PROJECT" ps -q kvnode 2>/dev/null | wc -l | tr -d ' ')
if [ "$running" -eq "$REPLICAS" ]; then
  ok "${running} kvnode containers are running"
else
  bad "expected ${REPLICAS} kvnode containers, found ${running}"
fi

# --- 4. wait for the proxy ------------------------------------------------
head_ "5. Reachability"
deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
up=false
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/health >/dev/null 2>&1; then
    up=true; break
  fi
  sleep 2
done

if $up; then
  ok "proxy answers /health on http://localhost:8080"
else
  bad "proxy never answered within ${BOOT_TIMEOUT}s"
  info "container logs:"
  "${DC[@]}" -p "$PROJECT" logs --tail 20 2>&1 | sed 's/^/        /'
  exit 1
fi

# --- 5. the actual point of the lab ---------------------------------------
head_ "6. Requests are spread across replicas"
# Section 5 only proves the PROXY answers, and it can do that as soon as ONE
# replica is up. Firing a single burst here and demanding all REPLICAS therefore
# fails a stack that is merely still starting -- a JVM booting behind a cold
# build -- with "requests are not spreading evenly", which sends the student to
# nginx.conf to debug a problem they do not have. Seen in a dry run, on a
# repository whose only change was an added comment line.
#
# So poll instead of sampling once: send a batch, remember which nodes answered,
# and stop as soon as all of them have. The sleep between batches also crosses
# nginx's 1s resolver TTL, so successive batches are not all served from a single
# cached DNS answer.
spread_deadline=$(( $(date +%s) + SPREAD_TIMEOUT ))
seen=""
rounds=0
while :; do
  rounds=$(( rounds + 1 ))
  for _ in $(seq 1 "$REQUESTS"); do
    r="$(curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/whoami 2>/dev/null)"
    [ -n "$r" ] && seen="${seen}${r}"$'\n'
  done
  ids="$(printf '%s' "$seen" | sort -u | sed '/^$/d')"
  distinct="$(printf '%s\n' "$ids" | grep -c . || true)"
  [ "$distinct" -ge "$REPLICAS" ] && break
  [ "$(date +%s)" -ge "$spread_deadline" ] && break
  sleep 2
done

info "${rounds} batch(es) of ${REQUESTS} requests reached ${distinct} distinct node(s):"
printf '%s\n' "$ids" | sed 's/^/          /'

if [ "$distinct" -ge "$REPLICAS" ]; then
  ok "all ${REPLICAS} replicas answered"
elif [ "$distinct" -gt 1 ]; then
  bad "only ${distinct} of ${REPLICAS} replicas answered within ${SPREAD_TIMEOUT}s"
  info "one replica may have failed to start -- check: docker compose ps"
  info "if all ${REPLICAS} are running, check the resolver line in proxy/nginx.conf"
else
  bad "every request hit the same node"
  info "nginx resolves a hard-coded upstream once at startup. Use a variable in"
  info "proxy_pass so it re-resolves per request -- see proxy/nginx.conf."
fi

# --- 6. the client container ----------------------------------------------
head_ "7. Client container"
if "${DC[@]}" -p "$PROJECT" exec -T client kv whoami >/dev/null 2>&1; then
  ok "'kv whoami' works from inside the client container"
else
  bad "could not run 'kv whoami' in the client container"
fi

# --- summary ---------------------------------------------------------------
printf '\n\033[1mSummary\033[0m\n'
printf '  %d passed, %d failed\n\n' "$pass" "$fail"

if [ "$fail" -eq 0 ]; then
  printf '\033[32mCP0 would PASS.\033[0m Tag and push:\n\n'
  printf '    git tag cp0 && git push origin cp0\n\n'
  printf 'Then paste your repository URL and the tag name into Canvas.\n\n'
  exit 0
else
  printf '\033[31mCP0 would FAIL.\033[0m Fix the items above and run this again.\n'
  printf 'Stuck? Post on the Canvas discussion board -- early beats late.\n\n'
  exit 1
fi
