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
if python3 - "$ROOT" <<'PY' 2>/dev/null
import subprocess, sys, json
try:
    import yaml  # optional
except ImportError:
    yaml = None
raw = subprocess.run(["docker","compose","config","--format","json"],
                     cwd=sys.argv[1], capture_output=True, text=True)
if raw.returncode != 0:
    sys.exit(2)
cfg = json.loads(raw.stdout)
ports = cfg.get("services", {}).get("kvnode", {}).get("ports", [])
sys.exit(1 if ports else 0)
PY
then
  ok "kvnode publishes no host port (required for scaling)"
else
  bad "kvnode publishes a host port -- only one replica can bind it, so --scale fails. Remove the ports: mapping; use expose: instead"
fi

# --- 2. build --------------------------------------------------------------
head_ "2. Build"
info "this can take a few minutes the first time"
if "${DC[@]}" -p "$PROJECT" build >/tmp/cs450-build.log 2>&1; then
  ok "all three images build"
else
  bad "build failed -- last 25 lines follow"
  tail -25 /tmp/cs450-build.log | sed 's/^/        /'
  exit 1
fi

# --- 3. bring the cluster up ----------------------------------------------
head_ "3. Start ${REPLICAS} replicas"
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
head_ "4. Reachability"
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
head_ "5. Requests are spread across replicas"
ids=$(for _ in $(seq 1 "$REQUESTS"); do
        curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/whoami 2>/dev/null
      done | sort -u)
distinct=$(printf '%s\n' "$ids" | grep -c . || true)

info "${REQUESTS} requests reached ${distinct} distinct node(s):"
printf '%s\n' "$ids" | sed 's/^/          /'

if [ "$distinct" -ge "$REPLICAS" ]; then
  ok "all ${REPLICAS} replicas answered"
elif [ "$distinct" -gt 1 ]; then
  bad "only ${distinct} of ${REPLICAS} replicas answered -- requests are not spreading evenly"
  info "check the resolver line in proxy/nginx.conf"
else
  bad "every request hit the same node"
  info "nginx resolves a hard-coded upstream once at startup. Use a variable in"
  info "proxy_pass so it re-resolves per request -- see proxy/nginx.conf."
fi

# --- 6. the client container ----------------------------------------------
head_ "6. Client container"
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
