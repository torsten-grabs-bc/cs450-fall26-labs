#!/usr/bin/env bash
#
# CS 450 Lab 2 -- self-check.
#
#   ./validate.sh          checks CP3   (membership list, Lamport clock)
#   ./validate.sh cp4      checks CP4   (adds the distributed lock)
#   ./validate.sh cp5      checks CP5   (adds two-phase commit)
#
# Each checkpoint includes the ones before it, and all of them re-check the
# five Lab 1 operations. A Lab 2 node that has stopped being a Lab 1 node is
# not finished.
#
# It performs exactly the checks the grader performs, so if this says PASS, the
# checkpoint passes. The grader picks the checkpoint up from the CP environment
# variable, so one file serves all three.
#
# It builds the stack, runs the checks, and tears everything down again. It
# also edits config/members.conf for one check and puts it back afterwards,
# including if you interrupt it.
#
set -uo pipefail

CP="${1:-${CP:-cp3}}"
case "$CP" in
  cp3|cp4|cp5) ;;
  *) echo "usage: $0 [cp3|cp4|cp5]" >&2; exit 2 ;;
esac

BOOT_TIMEOUT="${BOOT_TIMEOUT:-90}"
PROJECT="cs450-lab2-verify-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

MEMBERS_FILE="$ROOT/config/members.conf"
MEMBERS_BACKUP="/tmp/cs450-lab2-members-$$.conf"

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

# members.conf is YOUR file and one check below edits it. Put it back whatever
# happens -- a failed check, a Ctrl-C, a crash. If this script ever leaves your
# membership list modified, that is a bug in this script.
cleanup() {
  if [ -f "$MEMBERS_BACKUP" ]; then
    cp "$MEMBERS_BACKUP" "$MEMBERS_FILE" 2>/dev/null || true
    rm -f "$MEMBERS_BACKUP"
  fi
  "${DC[@]}" -p "$PROJECT" down --remove-orphans --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

printf '\033[1mCS 450 Lab 2 verification (%s)\033[0m\n' "$CP"
info "project root: $ROOT"

NODES="kvnode1 kvnode2 kvnode3"

# One request line in, one response line out, to one named node. Port 9090 is
# not published on any node, so every TCP check runs from inside the client
# container, exactly as the handout's commands do.
kvtcp() {   # kvtcp <node> <request>
  printf '%s\n' "$2" \
    | "${DC[@]}" -p "$PROJECT" exec -T client nc -w 10 "$1" 9090 2>/dev/null \
    | head -1 | tr -d '\r'
}

# Several request lines down one connection, all responses out.
kvtcp_many() {   # kvtcp_many <node> <request> [<request>...]
  local node="$1"; shift
  printf '%s\n' "$@" \
    | "${DC[@]}" -p "$PROJECT" exec -T client nc -w 10 "$node" 9090 2>/dev/null \
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

want() {  # description, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; info "expected: $2"; info "got:      $3"; fi
}

# CLOCK <n> node=<id>  ->  n.  Empty if the reply is not that shape.
clock_of() {
  local r="$1"
  case "$r" in
    "CLOCK "*" node="*) printf '%s' "$r" | cut -d' ' -f2 ;;
    *) printf '' ;;
  esac
}
is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Poll a node until it answers STATS, or give up.
wait_for_node() {   # wait_for_node <node> <seconds>
  local deadline=$(( $(date +%s) + $2 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    case "$(kvtcp "$1" 'STATS')" in STATS*) return 0 ;; esac
    sleep 1
  done
  return 1
}

# --- 1. compose file -------------------------------------------------------
head_ "1. Compose file"
CONFIG="$("${DC[@]}" config 2>/dev/null)"
if [ -z "$CONFIG" ]; then
  bad "'docker compose config' failed -- your compose file does not parse"
  exit 1
fi
for svc in kvnode1 kvnode2 kvnode3 proxy client; do
  if grep -qE "^  ${svc}:" <<<"$CONFIG"; then
    ok "service '${svc}' is defined"
  else
    bad "service '${svc}' is missing -- the grader addresses it by that exact name"
  fi
done
if grep -q "container_name" <<<"$CONFIG"; then
  bad "a service sets container_name -- remove it"
else
  ok "no service pins container_name"
fi

# Builtin-only, same as Lab 1: no interpreter, no external tools. Walks the
# rendered config and reports which top-level services have a ports: key.
services_publishing_ports() {
  local line svc="" out=""
  while IFS= read -r line; do
    case "$line" in
      "  "[![:space:]]*:*) svc="${line#  }"; svc="${svc%%:*}" ;;
      "    ports:"*) case " $out " in *" $svc "*) ;; *) out="$out $svc" ;; esac ;;
    esac
  done <<<"$CONFIG"
  printf '%s' "${out# }"
}
published="$(services_publishing_ports)"
offenders=""
for svc in $published; do
  case "$svc" in kvnode*) offenders="$offenders $svc" ;; esac
done
if [ -n "$offenders" ]; then
  bad "these nodes publish a host port:${offenders}"
  info "the proxy is still the only way in. Use expose:, not ports:"
else
  ok "no kvnode publishes a host port"
fi

# The membership file has to be the same file for all three nodes, and it has
# to be the directory that is mounted -- see the comment in docker-compose.yml.
if [ -f "$MEMBERS_FILE" ]; then
  ok "config/members.conf is present"
else
  bad "config/members.conf is missing -- it ships with the lab"
  exit 1
fi
mounts="$(grep -c '/etc/kv' <<<"$CONFIG")"
if [ "$mounts" -ge 3 ]; then
  ok "config/ is mounted into the nodes"
else
  warn "config/ does not look mounted into all three nodes"
  info "each kvnode wants:  - ./config:/etc/kv:ro"
fi

# --- 2. port 8080 ----------------------------------------------------------
# Finding what listens on a port has no portable command. lsof is on macOS, ss
# on most Linux, and Git Bash on Windows passes through Windows' netstat.
# Returns 0 = something is listening, 1 = nothing is, 2 = cannot tell.
# "Cannot tell" must never read as "free".
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
elif [ -n "$("${DC[@]}" -p cs450-lab2 ps -q proxy 2>/dev/null)$("${DC[@]}" -p cs450-lab1 ps -q proxy 2>/dev/null)" ]; then
  bad "port 8080 is held by your own stack, which is still running"
  info "this self-check starts its own copy, so shut yours down first:"
  info "    docker compose down"
  exit 1
else
  bad "port 8080 is already in use on your machine"
  info "find what is holding it:  $PORT_TOOL"
  info "do NOT change the port mapping -- the grader expects 8080"
  exit 1
fi

# --- 3. build --------------------------------------------------------------
head_ "3. Build"
info "this can take a few minutes the first time"
if "${DC[@]}" -p "$PROJECT" build >/tmp/cs450-lab2-build.log 2>&1; then
  ok "all images build"
else
  bad "build failed -- last 25 lines follow"
  tail -25 /tmp/cs450-lab2-build.log | sed 's/^/        /'
  exit 1
fi

# --- 4. start --------------------------------------------------------------
head_ "4. Start"
if "${DC[@]}" -p "$PROJECT" up -d >/tmp/cs450-lab2-up.log 2>&1; then
  ok "the stack starts"
else
  bad "compose up failed -- last 25 lines follow"
  tail -25 /tmp/cs450-lab2-up.log | sed 's/^/        /'
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
  ok "the cluster answers /health"
else
  bad "no node answered within ${BOOT_TIMEOUT}s"
  "${DC[@]}" -p "$PROJECT" logs --tail 20 2>&1 | sed 's/^/        /'
  exit 1
fi

if [ -n "$(curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/whoami 2>/dev/null)" ]; then
  ok "/whoami still works"
else
  bad "/whoami stopped working -- the harness and the graders still use it"
fi

# All three, individually, on the TCP port. Everything after this addresses
# them by name, so there is no point continuing if one of them is not there.
alldown=true
for n in $NODES; do
  if wait_for_node "$n" 30; then ok "$n answers on 9090"; alldown=false
  else bad "$n never answered STATS on port 9090"; fi
done
if $alldown; then
  "${DC[@]}" -p "$PROJECT" logs --tail 20 2>&1 | sed 's/^/        /'
  exit 1
fi

# --- 5. Lab 1 still works --------------------------------------------------
# Every reply here is read from the node the write went to, so this means the
# same thing at every checkpoint -- before replication exists and after.
head_ "5. The Lab 1 operations"
want "PUT returns OK"              "OK"                "$(kvtcp kvnode1 'PUT colour blue')"
want "GET returns the value"       "VALUE blue"        "$(kvtcp kvnode1 'GET colour')"
want "GET of a missing key"        "NOT_FOUND"         "$(kvtcp kvnode1 'GET nothing')"
want "values may contain spaces"   "VALUE hello there" "$(kvtcp_many kvnode1 'PUT greeting hello there' 'GET greeting' | tail -1)"
want "PUT replaces a value"        "VALUE green"       "$(kvtcp_many kvnode1 'PUT colour green' 'GET colour' | tail -1)"
want "DEL returns OK"              "OK"                "$(kvtcp_many kvnode1 'PUT tmp x' 'DEL tmp' | tail -1)"
want "DEL of a missing key"        "NOT_FOUND"         "$(kvtcp kvnode1 'DEL nothing')"

keys="$(kvtcp_many kvnode1 'PUT a 1' 'PUT b 2' 'KEYS' | tail -1)"
if [[ "$keys" == KEYS\ * ]] && grep -q 'a' <<<"$keys" && grep -q 'b' <<<"$keys"; then
  ok "KEYS lists the keys"
else
  bad "KEYS did not list the keys"; info "got: $keys"
fi

stats="$(kvtcp kvnode1 'STATS')"
if [[ "$stats" == STATS\ keys=*\ node=* ]]; then
  ok "STATS has the right shape"
else
  bad "STATS has the wrong shape"; info "expected: STATS keys=<n> node=<id>"; info "got:      $stats"
fi

err="$(kvtcp kvnode1 'put lower case')"
if [[ "$err" == ERR* ]]; then
  ok "a lower-case command is an error"
else
  bad "a lower-case command should return ERR"; info "got: $err"
fi

want "the connection survives a bad request" "VALUE green" \
     "$(kvtcp_many kvnode1 'nonsense' 'GET colour' | tail -1)"

# The proxy still round-robins, and before CP5 a key lives on one node only --
# so this asks for something every node can answer rather than for a key.
want "the REST door still opens" "200" "$(code GET /stats)"

# --- 6. CP3: membership and the clock --------------------------------------
head_ "6. The membership list"
for n in $NODES; do
  want "MEMBERS on $n" "MEMBERS kvnode1 kvnode2 kvnode3" "$(kvtcp "$n" 'MEMBERS')"
done
m_err="$(kvtcp kvnode1 'MEMBERS extra')"
if [[ "$m_err" == ERR* ]]; then
  ok "MEMBERS with an argument is an error"
else
  warn "MEMBERS takes no arguments, so 'MEMBERS extra' should be ERR"; info "got: $m_err"
fi

head_ "7. The Lamport clock"
# Everything here is relative. A node's clock depends on what has already
# happened to it, which is not the same number on every machine, and a check
# that hardcodes one would fail for a correct implementation.
b1="$(clock_of "$(kvtcp kvnode1 'CLOCK')")"
if is_number "$b1"; then
  ok "CLOCK has the right shape"
else
  bad "CLOCK has the wrong shape"
  info "expected: CLOCK <n> node=<id>"
  info "got:      $(kvtcp kvnode1 'CLOCK')"
fi

if is_number "$b1"; then
  t1="$(clock_of "$(kvtcp kvnode1 'TICK')")"
  if is_number "$t1" && [ "$t1" -gt "$b1" ]; then
    ok "TICK advances the clock"
  else
    bad "TICK did not advance the clock"
    info "was $b1, TICK answered: ${t1:-<wrong shape>}"
  fi

  c1="$(clock_of "$(kvtcp kvnode1 'CLOCK')")"
  if [ -n "$t1" ] && [ "$c1" = "$t1" ]; then
    ok "CLOCK does not advance the clock"
  else
    bad "CLOCK advanced the clock -- it only reports it"
    info "TICK left it at ${t1:-?}, then CLOCK answered ${c1:-?}"
    info "reading a clock is not an event. See LamportClock.java"
  fi

  # GOSSIP: one local event, a PING to each peer, each PONG folded back in.
  g="$(kvtcp kvnode1 'GOSSIP')"
  sent=""; now=""
  if [[ "$g" == OK\ sent=*\ now=* ]]; then
    sent="${g#OK sent=}"; sent="${sent%% *}"
    now="${g##*now=}"
    ok "GOSSIP has the right shape"
  else
    bad "GOSSIP has the wrong shape"
    info "expected: OK sent=<ts> now=<clock>"
    info "got:      $g"
  fi

  if is_number "$sent" && is_number "$now"; then
    if [ "$sent" -gt "$c1" ]; then
      ok "GOSSIP counts the send as an event"
    else
      bad "GOSSIP sent the clock's current value without advancing it first"
      info "the clock read $c1 before the gossip and it sent sent=$sent"
    fi
    if [ "$now" -gt "$sent" ]; then
      ok "the PONGs move the sender's clock too"
    else
      bad "the clock did not move after the PONGs came back"
      info "sent=$sent and now=$now. A reply is a message: it is an event at"
      info "the receiving end as well, twice here, once per peer."
    fi
    for n in kvnode2 kvnode3; do
      p="$(clock_of "$(kvtcp "$n" 'CLOCK')")"
      if is_number "$p" && [ "$p" -ge $(( sent + 1 )) ]; then
        ok "$n took the sender's timestamp into account"
      else
        bad "$n's clock reads ${p:-<wrong shape>} after a gossip carrying $sent"
        info "expected at least $(( sent + 1 ))"
        info "reading exactly $sent means you assigned the received value instead"
        info "of max(own, received) + 1. A small number means you ticked on"
        info "receipt and threw the sender's timestamp away."
      fi
    done
  fi
fi

head_ "8. RELOAD"
cp "$MEMBERS_FILE" "$MEMBERS_BACKUP"
keys_before="$(kvtcp kvnode1 'STATS')"
cid="$("${DC[@]}" -p "$PROJECT" ps -q kvnode1 2>/dev/null)"
started_before="$(docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null)"

# Comment out kvnode3, exactly as the handout tells students to do by hand.
sed 's/^[[:space:]]*kvnode3[[:space:]]/#kvnode3 /' "$MEMBERS_BACKUP" > "$MEMBERS_FILE"
if cmp -s "$MEMBERS_BACKUP" "$MEMBERS_FILE"; then
  warn "could not find a 'kvnode3 ...' line in config/members.conf to comment out"
  info "the file should have one 'kvnode<n> <host> <port>' line per member"
  info "skipping the RELOAD checks"
  cp "$MEMBERS_BACKUP" "$MEMBERS_FILE"
else
  reloaded="$(kvtcp kvnode1 'RELOAD')"
  want "RELOAD returns OK" "OK" "$reloaded"
fi

# Everything below depends on a reload having actually happened. Running it
# anyway would hand out passes for checks that could not have failed.
if [ "${reloaded:-}" != "OK" ]; then
  cp "$MEMBERS_BACKUP" "$MEMBERS_FILE"
  info "the rest of the RELOAD checks need a working RELOAD -- skipping them"
else
  want "the reloaded node has the new list" "MEMBERS kvnode1 kvnode2" "$(kvtcp kvnode1 'MEMBERS')"
  # Reload is per node: nothing told kvnode2 to re-read anything. Not graded --
  # a node that also re-reads on a timer is doing more than it was asked, not
  # something wrong.
  m2="$(kvtcp kvnode2 'MEMBERS')"
  if [ "$m2" = "MEMBERS kvnode1 kvnode2 kvnode3" ]; then
    ok "a node that was not reloaded is unchanged"
  elif [[ "$m2" == MEMBERS\ * ]]; then
    warn "kvnode2 was not reloaded but its list changed anyway"
    info "got: $m2"
    info "harmless if you re-read the file on a timer as well. Worth knowing."
  fi

  # The two things actually being graded here.
  want "the keys are still there after a reload" "$keys_before" "$(kvtcp kvnode1 'STATS')"
  started_after="$(docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null)"
  if [ -n "$started_before" ] && [ "$started_before" = "$started_after" ]; then
    ok "the node did not restart"
  elif [ -z "$started_before" ]; then
    warn "could not read the container's start time, so cannot tell whether it restarted"
  else
    bad "kvnode1 restarted when it reloaded"
    info "membership changing is an ordinary event in a running system."
    info "Re-read the file and replace the list. Do not start again."
  fi

  cp "$MEMBERS_BACKUP" "$MEMBERS_FILE"
  want "the list comes back after a second RELOAD" "MEMBERS kvnode1 kvnode2 kvnode3" \
       "$(kvtcp_many kvnode1 'RELOAD' 'MEMBERS' | tail -1)"

  # A file that will not parse must not take the old list down with it.
  printf 'this is not a member line\n' > "$MEMBERS_FILE"
  r="$(kvtcp kvnode1 'RELOAD')"
  if [[ "$r" == ERR* ]]; then
    ok "a file that will not parse answers ERR"
  else
    bad "a file that will not parse should answer ERR <reason>"; info "got: $r"
  fi
  want "and the old list survives it" "MEMBERS kvnode1 kvnode2 kvnode3" "$(kvtcp kvnode1 'MEMBERS')"
  cp "$MEMBERS_BACKUP" "$MEMBERS_FILE"
  kvtcp kvnode1 'RELOAD' >/dev/null
fi
rm -f "$MEMBERS_BACKUP"

# --- 9. CP4: the distributed lock ------------------------------------------
if [ "$CP" = "cp4" ] || [ "$CP" = "cp5" ]; then
  head_ "9. The lock protocol"
  want "a LOCK nobody is holding is granted" "GRANT vk" "$(kvtcp kvnode1 'LOCK vk 1 tester')"
  kvtcp kvnode1 'RELEASE vk 1 tester' >/dev/null
  l_err="$(kvtcp kvnode1 'LOCK vk')"
  if [[ "$l_err" == ERR* ]]; then
    ok "a LOCK missing its timestamp is an error"
  else
    bad "LOCK needs a key, a timestamp and a node -- 'LOCK vk' should be ERR"
    info "got: $l_err"
  fi

  head_ "10. Two nodes racing one key"
  # Five rounds, because one round can come out right by luck on a broken
  # implementation -- the two requests simply may not overlap.
  races_ok=true
  for round in 1 2 3 4 5; do
    ( kvtcp kvnode1 "PUT hot$round fromA" >/tmp/cs450-lab2-a.$$ 2>&1 ) &
    pa=$!
    ( kvtcp kvnode2 "PUT hot$round fromB" >/tmp/cs450-lab2-b.$$ 2>&1 ) &
    pb=$!
    wait $pa; wait $pb
    ra="$(cat /tmp/cs450-lab2-a.$$)"; rb="$(cat /tmp/cs450-lab2-b.$$)"
    if [ "$ra" != "OK" ] || [ "$rb" != "OK" ]; then
      bad "round $round: one of the two writers did not get OK"
      info "kvnode1 answered: ${ra:-<nothing>}"
      info "kvnode2 answered: ${rb:-<nothing>}"
      info "both writers should succeed. They take turns; neither is refused."
      races_ok=false
      break
    fi
    # Whatever each node holds has to be one of the two values, whole. A
    # spliced value means two writers were inside the store at once.
    for n in kvnode1 kvnode2; do
      v="$(kvtcp "$n" "GET hot$round")"
      case "$v" in
        "VALUE fromA"|"VALUE fromB") ;;
        *) bad "round $round: $n holds a value that is neither of the two written"
           info "got: $v"
           info "expected 'VALUE fromA' or 'VALUE fromB', not a mixture of them"
           races_ok=false ;;
      esac
    done
    $races_ok || break
  done
  rm -f /tmp/cs450-lab2-a.$$ /tmp/cs450-lab2-b.$$
  $races_ok && ok "five rounds of two nodes writing one key, no corruption"

  head_ "11. One node, several threads, one key"
  # This is the case Ricart & Agrawala does not cover. R&A orders nodes against
  # each other and says nothing about two connections into the same node.
  same_ok=true
  for round in 1 2 3; do
    for w in A B C; do
      ( kvtcp kvnode1 "PUT same$round from$w" >/dev/null 2>&1 ) &
    done
    wait
    n="$(kvtcp kvnode1 'KEYS' | tr ' ' '\n' | grep -c "^same$round\$")"
    if [ "$n" = "1" ]; then
      :
    elif [ "$n" = "0" ]; then
      bad "round $round: nothing was stored by the concurrent writes"
      info "that is not a locking problem -- section 5 has to pass first"
      same_ok=false
      break
    else
      bad "round $round: the key appears $n times -- expected 1"
      same_ok=false
    fi
    v="$(kvtcp kvnode1 "GET same$round")"
    case "$v" in
      "VALUE fromA"|"VALUE fromB"|"VALUE fromC") ;;
      *) bad "round $round: kvnode1 holds a value none of the three writers wrote"
         info "got: $v"
         info "three threads were inside the store at once. Ricart & Agrawala"
         info "orders nodes, not threads. Take the per-key local lock before the"
         info "distributed protocol starts -- see LockManager.java"
         same_ok=false ;;
    esac
    $same_ok || break
  done
  $same_ok && ok "three rounds of three threads writing one key through one node"

  # The cheapest proof that PUT consults its peers at all: take a peer away.
  # Without a GRANT from every other member the lock cannot be taken, so the
  # PUT must refuse rather than write anyway. At CP5 section 14 does this with
  # a transaction in the way as well, so it is not worth stopping a node twice.
  if [ "$CP" = "cp4" ]; then
  head_ "12. The lock really is in the path of a PUT"
  if "${DC[@]}" -p "$PROJECT" stop kvnode3 >/dev/null 2>&1; then
    before="$(kvtcp kvnode1 'GET quorum')"
    r="$(kvtcp kvnode1 'PUT quorum written-without-a-lock')"
    if [[ "$r" == ERR* ]]; then
      ok "with a member down, a PUT answers ERR instead of writing"
    else
      bad "with kvnode3 stopped, a PUT still answered: $r"
      info "the lock needs a GRANT from every other member. A node that is not"
      info "there cannot grant, so the lock cannot be taken, so the write does"
      info "not happen. A plain OK here means PUT never asked anyone."
    fi
    want "and nothing was written" "$before" "$(kvtcp kvnode1 'GET quorum')"
    "${DC[@]}" -p "$PROJECT" start kvnode3 >/dev/null 2>&1
    if wait_for_node kvnode3 "$BOOT_TIMEOUT"; then
      ok "kvnode3 comes back"
    else
      bad "kvnode3 did not come back within ${BOOT_TIMEOUT}s"
    fi
  else
    warn "could not stop kvnode3, so this check was skipped"
  fi
  fi
fi

# --- 12. CP5: two-phase commit ---------------------------------------------
if [ "$CP" = "cp5" ]; then
  head_ "12. Replication"
  want "a PUT is accepted" "OK" "$(kvtcp kvnode1 'PUT ripe yes')"
  want "the coordinator has it" "VALUE yes" "$(kvtcp kvnode1 'GET ripe')"
  for n in kvnode2 kvnode3; do
    want "and so does $n" "VALUE yes" "$(kvtcp "$n" 'GET ripe')"
  done

  # Any node can coordinate, not just the first one.
  want "a PUT through kvnode2 is accepted" "OK" "$(kvtcp kvnode2 'PUT second-hand ok')"
  for n in kvnode1 kvnode3; do
    want "kvnode2 can coordinate too -- $n has it" "VALUE ok" "$(kvtcp "$n" 'GET second-hand')"
  done

  # PREPARE carries the value last for exactly this reason.
  kvtcp kvnode1 'PUT motto all for one' >/dev/null
  for n in kvnode2 kvnode3; do
    want "a value with spaces survives the trip to $n" "VALUE all for one" "$(kvtcp "$n" 'GET motto')"
  done

  want "a replacing PUT is accepted" "OK" "$(kvtcp kvnode1 'PUT ripe no')"
  want "and the replacement reaches kvnode3" "VALUE no" "$(kvtcp kvnode3 'GET ripe')"

  head_ "13. All three, or none"
  if "${DC[@]}" -p "$PROJECT" stop kvnode3 >/dev/null 2>&1; then
    r="$(kvtcp kvnode1 'PUT ripe maybe')"
    if [[ "$r" == ERR* ]]; then
      ok "with a member down, a PUT answers ERR"
    else
      bad "with kvnode3 stopped, a PUT answered: $r"
      info "a participant that does not answer in time is an abort. Every member"
      info "has to vote, and a node that is not there cannot."
    fi
    for n in kvnode1 kvnode2; do
      want "$n still holds the old value" "VALUE no" "$(kvtcp "$n" 'GET ripe')"
    done

    "${DC[@]}" -p "$PROJECT" start kvnode3 >/dev/null 2>&1
    if wait_for_node kvnode3 "$BOOT_TIMEOUT"; then
      ok "kvnode3 comes back"
      # Not graded. The handout asks you to know what your implementation does
      # here and to say so in the write-up, so this reports rather than judges.
      back="$(kvtcp kvnode3 'GET ripe')"
      info "kvnode3 answers 'GET ripe' with: $back"
      case "$back" in
        "VALUE no")  info "it kept what it had committed before it was stopped, so its"
                     info "store outlives the process. That is the answer to talk about"
                     info "in the screencast." ;;
        NOT_FOUND)   info "it came back empty: its store lives in memory only. Say so in"
                     info "the write-up -- it is a real answer, and it is the reason a"
                     info "participant that has voted to commit cannot keep its promise"
                     info "across a restart." ;;
        *)           info "neither the old value nor NOT_FOUND. Worth understanding before"
                     info "you record the screencast." ;;
      esac
    else
      bad "kvnode3 did not come back within ${BOOT_TIMEOUT}s"
    fi
  else
    warn "could not stop kvnode3, so the all-or-none checks were skipped"
  fi

  head_ "14. Concurrent writers, now that disagreement shows"
  # The same race as section 10, but with replication in place the nodes can
  # finally be compared with each other. If the lock does not work, two
  # transactions interleave and the three nodes end up disagreeing.
  agreed=true
  for round in 1 2 3 4 5; do
    ( kvtcp kvnode1 "PUT race$round fromA" >/dev/null 2>&1 ) &
    ( kvtcp kvnode2 "PUT race$round fromB" >/dev/null 2>&1 ) &
    ( kvtcp kvnode3 "PUT race$round fromC" >/dev/null 2>&1 ) &
    wait
    v1="$(kvtcp kvnode1 "GET race$round")"
    v2="$(kvtcp kvnode2 "GET race$round")"
    v3="$(kvtcp kvnode3 "GET race$round")"
    if [ "$v1" = "$v2" ] && [ "$v2" = "$v3" ]; then
      case "$v1" in
        "VALUE fromA"|"VALUE fromB"|"VALUE fromC") ;;
        *) bad "round $round: all three agree on a value nobody wrote: $v1"; agreed=false ;;
      esac
    else
      bad "round $round: the three nodes disagree"
      info "kvnode1: $v1"
      info "kvnode2: $v2"
      info "kvnode3: $v3"
      info "three transactions on one key overlapped. The lock is what stops"
      info "that, and it has to be taken before the first PREPARE goes out."
      agreed=false
    fi
    $agreed || break
  done
  $agreed && ok "five rounds of three nodes writing one key, all three agree every time"
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
