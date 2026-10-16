#!/usr/bin/env bash
#
# CS 450 Lab 1 -- benchmark.
#
#   ./bench.sh --single|--multi <tcp|rest> <clients> <requests-per-client>
#
#   ./bench.sh --single tcp  1 500     # your CP1 server, one client at a time
#   ./bench.sh --multi  rest 4 500     # your CP2 server, concurrent clients
#
# The flag says which server you are measuring. --single appends to
# bench.single.txt, --multi to bench.multi.txt. It is not optional, because an
# unlabelled set of numbers is no use to you three weeks later when the write-up
# asks you to compare the two.
#
# The flag is checked, not taken on trust: if it does not match what your server
# actually does, nothing is written and the script tells you which flag to use.
#
# At CP1 run --single for tcp at 1 and 4 clients. At CP2 run --multi for both
# protocols at 1, 4 and 16 clients. The contents of both files go in the appendix
# of your Lab 1 write-up, which is submitted as one PDF. Everyone runs the same
# tool so that the numbers mean the same thing side by side on Nov 2.
#
# WHAT IT MEASURES, and what it does not.
#
# Two numbers, because they answer different questions.
#
#   throughput   requests per second with <clients> clients all going at once.
#                Each client pipelines its requests down one connection: it does
#                not wait for a reply before sending the next. That is the
#                server's best case and it is what you want for a throughput
#                figure, because it keeps the server busy.
#
# There is no latency column, and that is deliberate. There used to be one.
# Every way of measuring it from out here spends longer starting a client
# process than the request itself takes, so the figure tracked the measuring
# tool instead of your server -- it barely moved when the server changed. A
# number that does not respond to the thing it claims to measure is worse than
# no number at all. Throughput is the honest one, so throughput is what you get.
#
# It is timed from ONE clock, here on your machine, by starting a stopwatch
# before and stopping it after. That is the only honest thing a single machine
# can measure. If you wanted to know how long the request took to travel one
# way -- how much of it was the network out, the server, the network back --
# you would need the clock in the container and the clock on your machine to
# agree about what time it is. They do not, and making them agree is section
# 5.1. That is the first thing we will talk about at the debrief.
#
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./bench.sh --single|--multi <tcp|rest> <clients> <requests-per-client>

  --single   you are measuring a server that handles one client at a time
             -- your CP1 server. Results append to bench.single.txt
  --multi    you are measuring a server that handles concurrent clients
             -- your CP2 server. Results append to bench.multi.txt

  ./bench.sh --single tcp  1 500
  ./bench.sh --multi  rest 4 500

The flag is not optional. An unlabelled set of numbers is no use to you three
weeks later, when the write-up asks you to compare the two.
USAGE
  exit 2
}

MODE=""
case "${1:-}" in
  --single) MODE=single; shift ;;
  --multi)  MODE=multi;  shift ;;
  *)        usage ;;
esac

PROTO="${1:-}"
CLIENTS="${2:-4}"
REQUESTS="${3:-500}"

case "$PROTO" in
  tcp|rest) ;;
  *) usage ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
OUT="$ROOT/bench.$MODE.txt"

if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  echo "Could not find docker compose." >&2; exit 2
fi

command -v perl >/dev/null 2>&1 || { echo "perl is needed for timing and was not found." >&2; exit 2; }
now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'; }

# The stack has to be up already -- benchmarking something this script started
# a second ago would measure the JVM warming up, not your server.
if ! curl -fsS --max-time 3 --noproxy '*' http://127.0.0.1:8080/health >/dev/null 2>&1; then
  echo "The stack is not running. Start it first:" >&2
  echo "    docker compose up --build -d" >&2
  exit 1
fi

node="$(curl -s --noproxy '*' http://127.0.0.1:8080/whoami | tr -d '\n\r')"

# /health answers even when nothing is implemented, so prove the store works
# before measuring it. Benchmarking a stub produces numbers that look fine and
# mean nothing.
probe_key="__bench_probe_$$"
probe="$(printf 'PUT %s alive\nGET %s\n' "$probe_key" "$probe_key" \
         | "${DC[@]}" exec -T client nc -w 3 kvnode 9090 2>/dev/null | tr -d '\r' | tail -1)"
if [ "$probe" != "VALUE alive" ]; then
  echo >&2
  echo "The TCP store is not answering correctly, so there is nothing to measure." >&2
  echo "  sent:     PUT $probe_key alive, then GET $probe_key" >&2
  echo "  expected: VALUE alive" >&2
  echo "  got:      ${probe:-<nothing>}" >&2
  echo >&2
  echo "Run ./validate.sh first. If you changed the code, rebuild:" >&2
  echo "    docker compose up --build -d" >&2
  exit 1
fi

# --- the label is checked --------------------------------------------------
# Hold one connection open and busy, then send a request down a second one. A
# single-threaded server is inside readLine() on the first connection and never
# reaches accept(), so the second request goes unanswered. A server that hands
# each connection to its own thread answers it immediately.
#
# A direct test of the thing itself, rather than a guess from timings: a
# one-core machine shows little speed-up either way, and telling those two cases
# apart is the whole point of the comparison.
#
# The holder paces its lines with "nc -i 1" on purpose. BusyBox nc half-closes
# the write side as soon as its stdin has nothing more ready to send, and the
# server then reads EOF, closes the socket and goes back to accept() -- so an
# idle holder leaves the server free and every server looks concurrent. Pacing
# keeps real traffic on the connection for the whole probe window. The delay
# applies before the FIRST line too, so the replies land one per second from
# t=1. HELD is read at a fixed t=4 rather than after a sleep: the probe
# returns instantly against a threaded server and only takes its full two
# seconds when it goes unanswered, so anything relative to it drifts.
#
# HELD is how many replies the holder had collected by the time the probe
# finished. Fewer than two means the holder was not holding anything open, so
# the answer would be meaningless: say so instead of guessing.
printf 'checking the %s flag ... ' "--$MODE"
out="$("${DC[@]}" exec -T client sh -c '
  t0=$(date +%s)
  printf "PUT __bench_hold__ x\nGET __bench_hold__\nGET __bench_hold__\nGET __bench_hold__\nGET __bench_hold__\nGET __bench_hold__\n" \
    | nc -i 1 -w 12 kvnode 9090 > /tmp/bench_hold.out 2>&1 &
  holder=$!
  sleep 1
  echo "PROBE:$(printf "GET __bench_hold__\n" | nc -w 2 kvnode 9090 2>/dev/null | tr -d "\r" | tail -1)"
  while [ $(( $(date +%s) - t0 )) -lt 4 ]; do sleep 1; done
  echo "HELD:$(wc -l < /tmp/bench_hold.out | tr -d " ")"
  kill $holder 2>/dev/null
  exit 0
' 2>/dev/null | tr -d '\r')"

probe_reply="$(printf '%s\n' "$out" | sed -n 's/^PROBE://p')"
held_lines="$(printf '%s\n' "$out" | sed -n 's/^HELD://p')"
case "$held_lines" in ''|*[!0-9]*) held_lines=0 ;; esac

if [ -n "$probe_reply" ]; then actual=multi; else actual=single; fi

if [ "${BENCH_SKIP_LABEL_CHECK:-}" = 1 ]; then
  echo "skipped"
elif [ "$held_lines" -lt 2 ]; then
  echo "cannot tell"
  echo >&2
  echo "Could not hold a connection open long enough to test, so the --$MODE flag" >&2
  echo "was taken at face value. The numbers are being written; check the label at" >&2
  echo "the top of the file yourself." >&2
  echo >&2
elif [ "$actual" != "$MODE" ]; then
  echo "no"
  echo >&2
  if [ "$actual" = multi ]; then
    echo "Your server answered a second client while the first connection was still" >&2
    echo "open and busy, so it handles concurrent clients." >&2
  else
    echo "Your server did not answer a second client while the first connection was" >&2
    echo "still open and busy, so it serves one at a time." >&2
  fi
  echo >&2
  echo "Nothing was written. Re-run with --$actual." >&2
  echo >&2
  echo "(BENCH_SKIP_LABEL_CHECK=1 goes ahead anyway.)" >&2
  exit 1
else
  echo "ok"
fi
if [ "$PROTO" = rest ]; then
  rprobe="$(curl -s --noproxy '*' -X PUT --data alive "http://127.0.0.1:8080/kv/$probe_key" >/dev/null 2>&1;
            curl -s --noproxy '*' "http://127.0.0.1:8080/kv/$probe_key" | tr -d '\n\r')"
  if [ "$rprobe" != "alive" ]; then
    echo >&2
    echo "The REST endpoints are not answering correctly, so there is nothing to measure." >&2
    echo "  expected: alive" >&2
    echo "  got:      ${rprobe:-<nothing>}" >&2
    echo >&2
    echo "Run ./validate.sh cp2 first." >&2
    exit 1
  fi
fi
"${DC[@]}" exec -T client sh -c "printf 'DEL %s\nDEL __bench_hold__\n' '$probe_key' | nc -w 2 kvnode 9090" >/dev/null 2>&1

# --- warm up ---------------------------------------------------------------
# The JIT compiles your hot path after it has seen it a few thousand times.
# Measuring before that happens tells you about the interpreter, not your code.
printf 'warming up ... '
if [ "$PROTO" = tcp ]; then
  for i in $(seq 1 2000); do echo "PUT warm$i v"; done \
    | "${DC[@]}" exec -T client nc -w 5 kvnode 9090 >/dev/null 2>&1
else
  for i in $(seq 1 300); do
    curl -s -o /dev/null --noproxy '*' -X PUT --data v "http://127.0.0.1:8080/kv/warm$i"
  done
fi
echo "done"

# --- throughput ------------------------------------------------------------
printf 'throughput: %s clients x %s requests ... ' "$CLIENTS" "$REQUESTS"
start="$(now_ms)"
for c in $(seq 1 "$CLIENTS"); do
  if [ "$PROTO" = tcp ]; then
    ( for i in $(seq 1 "$REQUESTS"); do echo "PUT c$c-$i value$i"; done \
      | "${DC[@]}" exec -T client nc -w 10 kvnode 9090 >/dev/null 2>&1 ) &
  else
    ( "${DC[@]}" exec -T client sh -c \
        "i=1; while [ \$i -le $REQUESTS ]; do \
           curl -s -o /dev/null -X PUT --data value\$i http://proxy:8080/kv/c$c-\$i; \
           i=\$((i+1)); done" >/dev/null 2>&1 ) &
  fi
done
wait
end="$(now_ms)"
elapsed_ms=$(( end - start ))
[ "$elapsed_ms" -lt 1 ] && elapsed_ms=1
total=$(( CLIENTS * REQUESTS ))
throughput="$(perl -e "printf '%.0f', $total / ($elapsed_ms/1000)")"
echo "done"

# --- report ----------------------------------------------------------------
line="$(printf '%-5s clients=%-3s requests=%-6s elapsed=%6sms throughput=%7s req/s node=%s' \
        "$PROTO" "$CLIENTS" "$total" "$elapsed_ms" "$throughput" "$node")"

{
  if [ ! -s "$OUT" ]; then
    if [ "$MODE" = single ]; then
      echo "# CS 450 Lab 1 benchmark results -- SINGLE-THREADED server (one client at a time)"
    else
      echo "# CS 450 Lab 1 benchmark results -- MULTITHREADED server (concurrent clients)"
    fi
    echo "# throughput: pipelined, all clients at once."
    echo "# Timed on this machine's clock. See the comment at the top of bench.sh."
    echo "# $(date)"
    echo
  fi
  echo "$line"
} >> "$OUT"

echo
echo "$line"
echo
echo "appended to $(basename "$OUT")"
