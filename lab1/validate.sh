#!/usr/bin/env bash
#
# CS 450 Lab 1 -- self-check.
#
#   ./validate.sh          checks CP1   (TCP, five operations, one client)
#   ./validate.sh cp2      checks CP2   (adds REST, concurrency, benchmark)
#
# It performs exactly the checks the grader performs, so if this says PASS, the
# checkpoint passes. The grader picks the checkpoint up from the CP environment
# variable, so one file serves both.
#
# It builds the stack, runs the checks, and tears everything down again.
#
set -uo pipefail

CP="${1:-${CP:-cp1}}"
case "$CP" in
  cp1|cp2) ;;
  *) echo "usage: $0 [cp1|cp2]" >&2; exit 2 ;;
esac

BOOT_TIMEOUT="${BOOT_TIMEOUT:-90}"
PROJECT="cs450-lab1-verify-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

pass=0
fail=0
warnings=0
ok()    { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
warn()  { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warnings=$((warnings+1)); }
info()  { printf '        %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  echo "Could not find 'docker compose' or 'docker-compose'." >&2
  echo "Install Docker Desktop (or Docker Engine plus the Compose plugin) and try again." >&2
  exit 2
fi

cleanup() { "${DC[@]}" -p "$PROJECT" down --remove-orphans --volumes >/dev/null 2>&1 || true; }
trap cleanup EXIT

printf '\033[1mCS 450 Lab 1 verification (%s)\033[0m\n' "$CP"
info "project root: $ROOT"

# One request line in, one response line out. Port 9090 is not published, so
# every TCP check runs from inside the client container.
kvtcp() {
  printf '%s\n' "$1" \
    | "${DC[@]}" -p "$PROJECT" exec -T client nc -w 2 kvnode 9090 2>/dev/null \
    | head -1 | tr -d '\r'
}

# Several request lines in one connection, all responses out.
kvtcp_many() {
  printf '%s\n' "$@" \
    | "${DC[@]}" -p "$PROJECT" exec -T client nc -w 2 kvnode 9090 2>/dev/null \
    | tr -d '\r'
}

code() {   # method path [body] -> HTTP status code
  local m="$1" p="$2" b="${3-}"
  if [ -n "$b" ]; then
    curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -X "$m" --data "$b" "http://127.0.0.1:8080$p"
  else
    curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -X "$m" "http://127.0.0.1:8080$p"
  fi
}
body() {   # method path [body] -> response body
  local m="$1" p="$2" b="${3-}"
  if [ -n "$b" ]; then
    curl -s --noproxy '*' -X "$m" --data "$b" "http://127.0.0.1:8080$p"
  else
    curl -s --noproxy '*' -X "$m" "http://127.0.0.1:8080$p"
  fi
}

# --- 1. compose file -------------------------------------------------------
head_ "1. Compose file"
CONFIG="$("${DC[@]}" config 2>/dev/null)"
if [ -z "$CONFIG" ]; then
  bad "'docker compose config' failed -- your compose file does not parse"
  exit 1
fi
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

# Same builtin-only check as Lab 0: no interpreter, no external tools.
kvnode_publishes_a_port() {
  local line in_kvnode=0
  while IFS= read -r line; do
    case "$line" in
      "  kvnode:"*)      in_kvnode=1; continue ;;
      "  "[![:space:]]*) in_kvnode=0 ;;
    esac
    if [ "$in_kvnode" = 1 ]; then
      case "$line" in "    ports:"*) return 0 ;; esac
    fi
  done <<<"$CONFIG"
  return 1
}
if kvnode_publishes_a_port; then
  bad "kvnode publishes a host port -- only one replica can bind it. Use expose:"
else
  ok "kvnode publishes no host port"
fi

# --- 2. port 8080 ----------------------------------------------------------
head_ "2. Port 8080"
if ! command -v lsof >/dev/null 2>&1; then
  info "lsof not available -- skipping the port check"
elif ! lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
  ok "port 8080 is free"
elif [ -n "$("${DC[@]}" -p cs450-lab1 ps -q proxy 2>/dev/null)$("${DC[@]}" -p cs450 ps -q proxy 2>/dev/null)" ]; then
  bad "port 8080 is held by your own stack, which is still running"
  info "this self-check starts its own copy, so shut yours down first:"
  info "    docker compose down"
  exit 1
else
  bad "port 8080 is already in use on your machine"
  info "find what is holding it:  lsof -nP -iTCP:8080 -sTCP:LISTEN"
  info "do NOT change the port mapping -- the grader expects 8080"
  exit 1
fi

# --- 3. build --------------------------------------------------------------
head_ "3. Build"
info "this can take a few minutes the first time"
if "${DC[@]}" -p "$PROJECT" build >/tmp/cs450-lab1-build.log 2>&1; then
  ok "all three images build"
else
  bad "build failed -- last 25 lines follow"
  tail -25 /tmp/cs450-lab1-build.log | sed 's/^/        /'
  exit 1
fi

# --- 4. start --------------------------------------------------------------
head_ "4. Start"
# One replica. Lab 1 is a single-node store; spreading data across nodes is Lab 2.
if "${DC[@]}" -p "$PROJECT" up -d >/tmp/cs450-lab1-up.log 2>&1; then
  ok "the stack starts"
else
  bad "compose up failed -- last 25 lines follow"
  tail -25 /tmp/cs450-lab1-up.log | sed 's/^/        /'
  exit 1
fi

deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
up=false
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/health >/dev/null 2>&1; then
    up=true; break
  fi
  sleep 2
done
if $up; then
  ok "the node answers /health"
else
  bad "the node never answered within ${BOOT_TIMEOUT}s"
  "${DC[@]}" -p "$PROJECT" logs --tail 20 2>&1 | sed 's/^/        /'
  exit 1
fi

# Lab 0 routes must survive Lab 1.
if [ -n "$(curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/whoami 2>/dev/null)" ]; then
  ok "/whoami still works"
else
  bad "/whoami stopped working -- the harness and the graders still use it"
fi

# --- 5. the TCP protocol (CP1) ---------------------------------------------
head_ "5. The TCP protocol"
want() {  # description, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; info "expected: $2"; info "got:      $3"; fi
}

want "PUT returns OK"                 "OK"                 "$(kvtcp 'PUT colour blue')"
want "GET returns the value"          "VALUE blue"         "$(kvtcp 'GET colour')"
want "GET of a missing key"           "NOT_FOUND"          "$(kvtcp 'GET nothing')"
want "values may contain spaces"      "VALUE hello there"  "$(kvtcp_many 'PUT greeting hello there' 'GET greeting' | tail -1)"
want "PUT replaces a value"           "VALUE green"        "$(kvtcp_many 'PUT colour green' 'GET colour' | tail -1)"
want "DEL returns OK"                 "OK"                 "$(kvtcp_many 'PUT tmp x' 'DEL tmp' | tail -1)"
want "DEL of a missing key"           "NOT_FOUND"          "$(kvtcp 'DEL nothing')"

keys="$(kvtcp_many 'PUT a 1' 'PUT b 2' 'KEYS' | tail -1)"
if [[ "$keys" == KEYS\ * ]] && grep -q 'a' <<<"$keys" && grep -q 'b' <<<"$keys"; then
  ok "KEYS lists the keys"
else
  bad "KEYS did not list the keys"; info "got: $keys"
fi

stats="$(kvtcp 'STATS')"
if [[ "$stats" == STATS\ keys=*\ node=* ]]; then
  ok "STATS has the right shape"
else
  bad "STATS has the wrong shape"; info "expected: STATS keys=<n> node=<id>"; info "got:      $stats"
fi

err="$(kvtcp 'put lower case')"
if [[ "$err" == ERR* ]]; then
  ok "a lower-case command is an error"
else
  bad "a lower-case command should return ERR"; info "got: $err"
fi

after_err="$(kvtcp_many 'nonsense' 'GET colour' | tail -1)"
want "the connection survives a bad request" "VALUE green" "$after_err"

# --- 6. the REST protocol (CP2) --------------------------------------------
if [ "$CP" = "cp2" ]; then
  head_ "6. The REST protocol"
  want "PUT /kv/<key>"           "200" "$(code PUT /kv/city Seattle)"
  want "GET /kv/<key>"           "200" "$(code GET /kv/city)"
  want "GET returns the value"   "Seattle" "$(body GET /kv/city | tr -d '\n')"
  want "GET of a missing key"    "404" "$(code GET /kv/nowhere)"
  want "DELETE /kv/<key>"        "200" "$(code DELETE /kv/city)"
  want "DELETE of a missing key" "404" "$(code DELETE /kv/nowhere)"
  want "an unsupported method"   "405" "$(code POST /kv/city)"

  curl -s --noproxy '*' -X PUT --data 'x' http://127.0.0.1:8080/kv/one >/dev/null
  if [ "$(code GET /kv)" = "200" ] && body GET /kv | grep -q '^one$'; then
    ok "GET /kv lists the keys"
  else
    bad "GET /kv did not list the keys"
  fi

  if [[ "$(body GET /stats)" == keys=*node=* ]]; then
    ok "GET /stats has the right shape"
  else
    bad "GET /stats has the wrong shape"; info "expected: keys=<n> node=<id>"
  fi

  # One store behind both doors.
  curl -s --noproxy '*' -X PUT --data 'via-rest' http://127.0.0.1:8080/kv/shared >/dev/null
  want "a REST write is visible over TCP" "VALUE via-rest" "$(kvtcp 'GET shared')"
  kvtcp 'PUT shared2 via-tcp' >/dev/null
  want "a TCP write is visible over REST" "via-tcp" "$(body GET /kv/shared2 | tr -d '\n')"

  # --- 7. concurrency ------------------------------------------------------
  head_ "7. Concurrent clients"
  # Hold one connection open, then see whether a second client is served while
  # the first is still connected. A single-threaded accept loop will not answer
  # until the first client goes away.
  ( printf 'STATS\n'; sleep 6 ) \
    | "${DC[@]}" -p "$PROJECT" exec -T client nc kvnode 9090 >/dev/null 2>&1 &
  holder=$!
  sleep 1
  started=$(date +%s)
  second="$(kvtcp 'STATS')"
  elapsed=$(( $(date +%s) - started ))
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  if [[ "$second" == STATS* ]] && [ "$elapsed" -lt 4 ]; then
    ok "a second client is served while the first is still connected"
  else
    bad "a second client was not served while the first was connected"
    info "it took ${elapsed}s and returned: ${second:-<nothing>}"
    info "give each connection its own thread -- see TcpServer.java"
  fi

  # Two writers on the same key. The key must appear exactly once afterwards.
  for w in A B; do
    ( for i in $(seq 1 200); do echo "PUT hot $w$i"; done \
      | "${DC[@]}" -p "$PROJECT" exec -T client nc -w 3 kvnode 9090 >/dev/null 2>&1 ) &
  done
  wait
  n="$(kvtcp 'KEYS' | tr ' ' '\n' | grep -c '^hot$')"
  # Zero and two mean different things. Zero means nothing was stored at all,
  # which is a CP1 problem, not a race -- do not send someone hunting for a
  # concurrency bug they do not have.
  if [ "$n" = "1" ]; then
    ok "the key appears exactly once after concurrent writes"
  elif [ "$n" = "0" ]; then
    bad "nothing was stored by the concurrent writes"
    info "that is not a concurrency problem -- the TCP checks above have to pass first"
  else
    bad "after concurrent writes the key appears $n times -- expected 1"
    info "two threads inserted it at the same moment. Your map is not safe under"
    info "concurrent access. See Store.java"
  fi

  # --- 8. benchmark --------------------------------------------------------
  # Checks that the benchmark was RUN, not just that the script is here. The
  # Lab 1 write-up is a table of these numbers, and a passing cp2 tag with no
  # measurements behind it is the one failure mode this catches cheaply.
  head_ "8. Benchmark"
  if [ -x ./bench.sh ]; then
    ok "bench.sh is present and executable"
  else
    bad "bench.sh is missing or not executable -- it ships with the lab"
  fi

  # count result lines, ignoring the comment header and blank lines
  count_runs() {
    # grep -c prints 0 AND exits 1 when nothing matches, so capture, don't chain
    [ -f "$1" ] || { echo 0; return; }
    c="$(grep -c '^[a-z]' "$1" 2>/dev/null || true)"
    case "$c" in ''|*[!0-9]*) echo 0 ;; *) echo "$c" ;; esac
  }

  runs="$(count_runs bench.multi.txt)"
  if [ "$runs" -eq 0 ]; then
    bad "no benchmark results -- bench.multi.txt is missing or has no runs in it"
    info "your Lab 1 write-up is a table of these numbers. Run:"
    info "    ./bench.sh --multi tcp 1 500    (then 4 and 16, then the same for rest)"
  elif [ "$runs" -lt 6 ]; then
    warn "bench.multi.txt has $runs run(s) -- the handout asks for 6"
    info "both protocols at 1, 4 and 16 clients. Each run appends to the file."
  else
    ok "bench.multi.txt has $runs runs in it"
  fi

  singleruns="$(count_runs bench.single.txt)"
  if [ "$singleruns" -eq 0 ]; then
    warn "no bench.single.txt -- the single-threaded numbers for the write-up"
    info "this does not fail the checkpoint. You tagged cp1, so you can still"
    info "take them:"
    info "    git stash && git checkout cp1"
    info "    docker compose up --build -d && ./bench.sh --single tcp 1 500"
    info "    git checkout main && git stash pop"
  else
    ok "bench.single.txt has $singleruns run(s) -- the single-threaded comparison"
  fi
fi

# --- summary ---------------------------------------------------------------
printf '\n\033[1mSummary\033[0m\n'
if [ "$warnings" -gt 0 ]; then
  printf '  %d passed, %d failed, %d warning(s)\n' "$pass" "$fail" "$warnings"
  printf '  Warnings do not fail the checkpoint. Read them before you write up.\n\n'
else
  printf '  %d passed, %d failed\n\n' "$pass" "$fail"
fi

if [ "$fail" -eq 0 ]; then
  printf '\033[32m%s would PASS.\033[0m Submit:\n\n' "$(tr a-z A-Z <<<"$CP")"
  printf '    ../scripts/submit.sh %s\n\n' "$CP"
  exit 0
else
  printf '\033[31m%s would FAIL.\033[0m Fix the items above and run this again.\n' "$(tr a-z A-Z <<<"$CP")"
  printf 'Stuck? Post on the Canvas discussion board -- early beats late.\n\n'
  exit 1
fi
