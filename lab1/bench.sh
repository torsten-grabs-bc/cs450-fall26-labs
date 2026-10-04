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
#   latency      mean round-trip time for a single request on a fresh
#                connection, measured serially with nobody else running. That
#                includes the TCP handshake, and for REST the HTTP request and
#                response headers too. It is the number a user would feel.
#
#                Both protocols are timed from INSIDE the client container, in
#                one `docker compose exec` for the whole loop. An earlier
#                version paid one exec per sample, and `docker compose exec`
#                costs tens of milliseconds to start -- so it reported Docker's
#                process startup and called it network latency. If you ever see
#                a latency figure that does not move when the server changes,
#                suspect the instrument before you believe the number.
#
# Both are timed from ONE clock, here on your machine, by starting a stopwatch
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
LATENCY_SAMPLES="${LATENCY_SAMPLES:-30}"

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
# Hold one connection open and idle, then send a request down a second one. A
# server that serves the connection it just accepted is stuck in a blocking read
# on the first one, so the second request goes unanswered. A server that hands
# each connection to its own thread answers it immediately.
#
# A direct test of the thing itself, rather than a guess from timings: a
# one-core machine shows little speed-up either way, and telling those two cases
# apart is the whole point of the comparison.
printf 'checking the %s flag ... ' "--$MODE"
conc="$("${DC[@]}" exec -T client sh -c '
  ( sleep 5 | nc -w 6 kvnode 9090 >/dev/null 2>&1 ) &
  holder=$!
  sleep 1
  printf "GET __bench_conc_probe__\n" | nc -w 2 kvnode 9090 2>/dev/null
  kill $holder 2>/dev/null
  exit 0
' 2>/dev/null | tr -d '\r' | tail -1)"

if [ -n "$conc" ]; then actual=multi; else actual=single; fi

if [ "${BENCH_SKIP_LABEL_CHECK:-}" = 1 ]; then
  echo "skipped"
elif [ "$actual" != "$MODE" ]; then
  echo "no"
  echo >&2
  if [ "$actual" = multi ]; then
    echo "Your server answered a second client while the first connection was still" >&2
    echo "open, so it handles concurrent clients." >&2
  else
    echo "Your server did not answer a second client while the first connection was" >&2
    echo "still open, so it serves one at a time." >&2
  fi
  echo >&2
  echo "Nothing was written. Re-run with --$actual." >&2
  echo >&2
  echo "(A single-threaded server that closes idle connections looks concurrent to" >&2
  echo " this check. BENCH_SKIP_LABEL_CHECK=1 goes ahead anyway.)" >&2
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
"${DC[@]}" exec -T client sh -c "printf 'DEL %s\n' '$probe_key' | nc -w 2 kvnode 9090" >/dev/null 2>&1

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

# --- latency ---------------------------------------------------------------
# Serial, one request per connection, nothing else running.
printf 'latency: %s single requests ... ' "$LATENCY_SAMPLES"
# One exec for the whole loop, and the loop runs inside the container for both
# protocols -- same instrument, same vantage point. Timed with the container's
# own clock, which is the only one that sees both ends of these requests.
if [ "$PROTO" = tcp ]; then
  inner="i=1; while [ \$i -le $LATENCY_SAMPLES ]; do \
           printf 'GET warm1\\n' | nc -w 2 kvnode 9090 >/dev/null; \
           i=\$((i+1)); done"
else
  inner="i=1; while [ \$i -le $LATENCY_SAMPLES ]; do \
           curl -s -o /dev/null http://proxy:8080/kv/warm1; \
           i=\$((i+1)); done"
fi
lat_raw="$("${DC[@]}" exec -T client sh -c \
  "s=\$(date +%s%N); $inner; e=\$(date +%s%N); echo \$(( (e - s) / 1000000 ))" 2>/dev/null \
  | tr -d '\r')"
case "$lat_raw" in
  ''|*[!0-9]*)
    latency="n/a"
    echo "failed"
    echo "  could not time inside the container (busybox date without %N?)" >&2
    ;;
  *)
    latency="$(perl -e "printf '%.2f', $lat_raw / $LATENCY_SAMPLES")"
    echo "done"
    ;;
esac

# --- report ----------------------------------------------------------------
line="$(printf '%-5s clients=%-3s requests=%-6s elapsed=%6sms throughput=%7s req/s latency=%8sms node=%s' \
        "$PROTO" "$CLIENTS" "$total" "$elapsed_ms" "$throughput" "$latency" "$node")"

{
  if [ ! -s "$OUT" ]; then
    if [ "$MODE" = single ]; then
      echo "# CS 450 Lab 1 benchmark results -- SINGLE-THREADED server (one client at a time)"
    else
      echo "# CS 450 Lab 1 benchmark results -- MULTITHREADED server (concurrent clients)"
    fi
    echo "# throughput: pipelined, all clients at once."
    echo "# latency:    one request per connection, serial, measured alone."
    echo "# Both timed on this machine's clock. See the comment at the top of bench.sh."
    echo "# $(date)"
    echo
  fi
  echo "$line"
} >> "$OUT"

echo
echo "$line"
echo
echo "appended to $(basename "$OUT")"
