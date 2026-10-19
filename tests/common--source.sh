#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Common utilities for unit tests

# Which booth a test runs — resolve_booth_bin / find_local_booth_build. Sourced
# here so every suite that pulls in this file gets them without a second source
# line; see booth-bin--source.sh for why the lookup is not inlined any more.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/booth-bin--source.sh"

# Host OS tag matching the codingbooth CLI's HOST_OS env var.
# Tests use this in their expected-output fixtures.
case "$(uname -s)" in
  Linux*)               HOST_OS="LIN" ;;
  Darwin*)              HOST_OS="MAC" ;;
  MINGW*|MSYS*|CYGWIN*) HOST_OS="WIN" ;;
  *)                    HOST_OS="$(uname -s)" ;;
esac
export HOST_OS

# A booth that serves a UI opens it in the host's browser by default, and in
# daemon mode the run does not return until the port answers. Neither belongs in
# a test: a suite would throw a window at whoever is running it, once per booth,
# and pay the wait for a page nothing is going to look at.
#
# Set here rather than per test so it covers a test run on its own as well as one
# run by a suite; the suite runners set it too, for the few tests that do not
# source this file. Only basic/test019--browser-open.sh unsets it — the default
# is the thing it tests.
export CB_BROWSER=false

# Run on Docker unless the caller picked an engine. With nothing chosen the CLI
# prefers Apple container when it is installed and running, so the engine — and
# every dryrun's expected `docker \` lines — would depend on the machine.
# CB_ENGINE=apple (or podman) runs a suite on that engine on purpose.
export CB_ENGINE="${CB_ENGINE:-docker}"

# How tests/setups/* run an install or setup script that insists on being root.
#
# Those scripts open with `[[ $EUID -eq 0 ]] || exit`, because inside a booth
# they run as root and hand the real work to `sudo -u coder`. A test running one
# on the host is not root — and does not need to be: it stubs `sudo` and the tool
# binary, then asserts on the command line the script emits. Nothing privileged
# is ever attempted, so the guard is the only thing in the way.
#
# bash takes EUID from the environment when one is present (checked on the 3.2
# macOS ships and the 5.2 in the image), so `env EUID=0` satisfies that guard
# with no privilege at all. It replaces fakeroot, which did the same job by
# faking uid 0 but is a package macOS does not have — so every one of these
# tests skipped on a Mac, and the suite still reported itself green.
#
# Use at the call site. The +"..." form is required: under bash 3.2, "${arr[@]}"
# on an *empty* array counts as unbound and `set -u` kills the test.
#
#     ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$SCRIPT" ...
#
ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    ROOT_RUN=(env EUID=0)
fi

# Running a booth with no controlling terminal.
#
# A booth that can reach the host as root asks for consent on /dev/tty, not on
# stdin, so it still works under `booth shell --run`. Redirecting or closing
# stdin therefore proves nothing: the only way to test the refusal is to take
# the terminal itself away, which means putting the command in a session of its
# own. On Linux that is what `setsid` is for.
#
# macOS has no setsid — it is util-linux. Without a fallback, every assertion in
# basic/test029 dies on `setsid: command not found`, and the weakest of them
# passes *because* of it: "non-zero status and no container" is satisfied just
# as well by a missing binary as by booth refusing. Green for the wrong reason,
# the same trap the ROOT_RUN note above describes.
#
# python3 and perl both expose setsid(2), and macOS ships perl, so in practice
# one of the three is always present. The fork matters: setsid(2) fails with
# EPERM for a process that already leads its group, and a freshly forked child
# never does. All three forms wait for the child and exit with its status, and
# leave stdout/stderr on the caller's fds so $(...) still captures them.
#
#     no_tty_supported || exit 0          # once, near the top of the test
#     OUTPUT=$(no_tty_run "$BOOTH" ...)   # per run
#
# --dind and --egress are not supported on Apple container yet: both share a
# sidecar's network namespace, which a per-booth VM cannot do (see
# docs/CONTAINER_SUPPORT.md, "Not supported: --dind and --egress"). The suites
# pin CB_ENGINE=docker, so this only bites a run made on purpose with
# CB_ENGINE=apple; a test that needs either then skips instead of failing:
#
#     sidecars_supported --dind || exit 0      # right after sourcing this file
#
sidecars_supported() {
    local engine
    engine="$(printf '%s' "${CB_ENGINE:-docker}" | tr '[:upper:]' '[:lower:]')"
    [[ "$engine" == "apple" ]] || return 0
    echo "SKIP: $* is not supported on engine apple (Apple container) yet — see docs/CONTAINER_SUPPORT.md." >&2
    return 1
}

# have_python3 reports whether `python3` is a Python that actually runs here.
#
# `command -v python3` does not answer that question on Windows. A stock PATH
# carries the App Execution Aliases in %LOCALAPPDATA%\Microsoft\WindowsApps —
# stubs named `python3` and `python` whose only job is to send whoever runs them
# to the Microsoft Store:
#
#     $ python3 -c 'print(1)'
#     Python was not found; run without arguments to install from the Microsoft
#     Store, or disable this shortcut from Settings > Apps > ...
#     $ echo $?
#     49
#
# `command -v` finds that, so every caller that only asked whether python3
# exists took the python3 branch and then watched it fail — the same "green (or
# red) for the wrong reason" trap as the ROOT_RUN and setsid notes above.
# port_is_bindable read exit 49 as "that port is taken", for all 100 candidates,
# and pick_free_port gave up on a host with twelve thousand free ports — taking
# every port-publishing test in basic/ with it. Ask for a Python that runs.
#
# The probe runs once per shell; the answer is cached for the rest of the suite.
have_python3() {
    if [[ -z "${_CB_HAVE_PYTHON3:-}" ]]; then
        if python3 -c '' >/dev/null 2>&1; then
            _CB_HAVE_PYTHON3=yes
        else
            _CB_HAVE_PYTHON3=no
        fi
    fi
    [[ "$_CB_HAVE_PYTHON3" == yes ]]
}

# serve_dir_http DIR : serve DIR's files over HTTP on 127.0.0.1, on a free port,
# until killed. Run it in the background and read the port with http_port_of:
#
#     serve_dir_http "$dir" & server_pid=$!
#     port=$(http_port_of "$dir") || { kill $server_pid; ...; }
#
# `python3 -m http.server` was the only server the tests stood up, and on a
# Windows host python3 is usually the Store stub (see have_python3), so the URL
# came out as http://localhost:/x and the test failed on something it was not
# testing. perl is the fallback for the reason no_tty_run reaches for it: Git
# Bash and macOS both ship it. GET of a plain file is all a test needs.
#
# The port goes to DIR/.http-port. The server runs from inside DIR so neither
# side has to translate a /tmp path for a native Windows Python. It execs, so
# killing the background job's pid kills the server itself.
serve_dir_http() {
    cd "$1" || return 1
    rm -f .http-port
    if have_python3; then
        exec python3 -c '
import http.server, socketserver, os
s = socketserver.TCPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
with open(".http-port.tmp", "w") as f: f.write(str(s.server_address[1]))
os.replace(".http-port.tmp", ".http-port")
s.serve_forever()
'
    fi
    exec perl -MIO::Socket::INET -e '
my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0,
                              Listen => 5, ReuseAddr => 1) or die "listen: $!\n";
open(my $f, ">", ".http-port.tmp") or die; print $f $s->sockport; close $f;
rename(".http-port.tmp", ".http-port") or die;
while (my $c = $s->accept) {
    my $req = <$c> // "";
    while (my $line = <$c>) { last if $line =~ /^\r?\n$/ }
    my ($path) = $req =~ m{^GET\s+/([^\s?]*)};
    my $body;
    if (defined $path && $path !~ m{\.\.} && -f $path && open(my $in, "<:raw", $path)) {
        local $/; $body = <$in>; close $in;
        print $c "HTTP/1.0 200 OK\r\nContent-Length: " . length($body) . "\r\nConnection: close\r\n\r\n$body";
    } else {
        print $c "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    }
    close $c;
}
'
}

# http_port_of DIR : the port serve_dir_http DIR is listening on, waiting up to
# 10s for it to come up. Fails (and prints nothing) if it never does.
http_port_of() {
    local i
    for i in $(seq 1 50); do
        if [[ -s "$1/.http-port" ]]; then
            cat "$1/.http-port"
            return 0
        fi
        sleep 0.2
    done
    return 1
}

no_tty_supported() {
    command -v setsid  >/dev/null 2>&1 && return 0
    have_python3 && return 0
    command -v perl    >/dev/null 2>&1 && return 0
    echo "SKIP: no setsid, python3 or perl here — cannot run a booth without a controlling terminal." >&2
    return 1
}

no_tty_run() {
    if command -v setsid >/dev/null 2>&1; then
        setsid -w "$@"
    elif have_python3; then
        python3 -c '
import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    try:
        os.execvp(sys.argv[1], sys.argv[1:])
    except OSError as err:
        sys.stderr.write("%s: %s\n" % (sys.argv[1], err))
        os._exit(127)
_, status = os.waitpid(pid, 0)
os._exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status))
' "$@"
    elif command -v perl >/dev/null 2>&1; then
        perl -MPOSIX -e '
my $pid = fork();
defined $pid or die "fork: $!\n";
if ($pid == 0) {
    POSIX::setsid();
    exec { $ARGV[0] } @ARGV;
    print STDERR "$ARGV[0]: $!\n";
    POSIX::_exit(127);
}
waitpid($pid, 0);
exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
' "$@"
    else
        echo "no_tty_run: no setsid, python3 or perl — guard the test with no_tty_supported" >&2
        return 1
    fi
}

# ── GNU tools a Mac does not have ────────────────────────────────────────────
#
# The suites were written against GNU userland, and three of the tools they
# reach for behave differently (or are simply absent) on macOS. Each one failed
# the same way: not "assertion false" but the test dying, or comparing against
# an empty string, which reads as a product bug until you look at stderr.
#
#   timeout        util-linux; macOS ships nothing. `timeout: command not
#                  found` under `set -e` takes the whole line with it, so the
#                  variable the test was going to assert on is "".
#   script         both have it, with incompatible syntax: util-linux takes
#                  `script -qec CMD FILE`, BSD takes `script -q -e FILE CMD…`.
#   touch -d       GNU parses relative dates ("1 year ago"); BSD wants an
#                  absolute stamp via -t, and rejects the rest outright.
#
# Homebrew's coreutils, when installed, provides gtimeout; the fallback below
# does not assume it. perl is the last resort for the same reason no_tty_run
# uses it: macOS ships it, and alarm(2) plus a fork is all a watchdog needs.

# timeout_run [-s SIG] SECONDS CMD... : run CMD, signalling it after SECONDS.
# Exits with CMD's status, or 124 when the time ran out (as timeout does).
#
# The signal is put back to its default disposition in CMD before CMD starts,
# because the suite runner may have taken it away. run-automate-tests.sh runs
# each suite as an asynchronous job — `( … ) &` — and POSIX has a shell with no
# job control ignore SIGINT and SIGQUIT in such a job. SIG_IGN survives exec, so
# every descendant inherits it: the suite runner, the test, and CMD. Nothing
# downstream can lift it either — a signal ignored on entry to a shell can
# neither be trapped nor reset there — so `-s INT` is simply swallowed, and a
# test that interrupts `booth logs -f` waits for a CLI that cannot die (which is
# what parked basic/test032--logs.sh for an hour and a half). GNU timeout
# un-ignores the signal itself; the uutils timeout and a bare fork do not, so the
# shim goes in front of all three rather than only where it is known to be
# missing.
#
# GRACE seconds after the signal, CMD is killed outright: a CMD that will not
# answer should fail its test, not hold up the suite behind it. That case exits
# 137, as timeout's own -k does, to tell "it died of the signal" (124) from "it
# had to be killed" (137).
timeout_run() {
    local signal=TERM
    if [[ "${1:-}" == "-s" ]]; then
        signal="$2"; shift 2
    fi
    signal="${signal#SIG}"   # INT, not SIGINT: a perl %SIG key, and what -s takes
    local seconds="$1" grace=5; shift

    # Terminal access must not stop CMD.
    #
    # Every branch below runs CMD in a process group of its own, which is never
    # the terminal's foreground group. A read of the terminal from such a group
    # raises SIGTTIN, a tcsetattr raises SIGTTOU, and either one stops the whole
    # group — CMD, its children, and the perl watchdog with them. A stopped
    # watchdog never fires, so the call does not time out: it waits forever. Run
    # from a shell, booth saw a terminal on stdin, started `docker run -i`,
    # docker read the terminal, and complex/test-boothfile-bash sat for 2.5h on
    # one `bash-3.2 --version`. CI has no terminal, so only a run from a shell
    # ever sees it.
    #
    # Ignoring the two signals is what makes that read fail instead of freeze:
    # the kernel skips the stop for a process that ignores the signal and the
    # read returns EIO, so CMD fails its test in a second and the suite moves on.
    # SIG_IGN survives exec, so it reaches CMD's own children — the docker CLI
    # included, which is the one that actually touches the terminal. CMD's stdin
    # is left as it is: a stdin the caller piped in still reaches CMD, and a test
    # that needs a terminal of its own still gets one from pty_run.
    #
    # What the TTOU half gives up: a tcsetattr from the background now succeeds
    # instead of stopping, so a CMD killed between "set raw" and "restore" leaves
    # the terminal as it set it (`stty sane` puts it back). That is the trade the
    # other way round from a suite that sits for hours, which is what it did.
    #
    # perl -e '…' SIG CMD… : un-ignore SIG, ignore the two stop signals, then
    # *become* CMD, so the pid the watchdog signals is still CMD's own.
    local -a unignore=()
    if command -v perl >/dev/null 2>&1; then
        unignore=(perl -e '
my $signal = shift;
$SIG{$signal} = "DEFAULT";
$SIG{TTIN} = "IGNORE";
$SIG{TTOU} = "IGNORE";
exec { $ARGV[0] } @ARGV;
print STDERR "$ARGV[0]: $!\n";
exit(127);
' "$signal")
    fi
    set -- ${unignore[@]+"${unignore[@]}"} "$@"

    if command -v timeout >/dev/null 2>&1; then
        timeout -s "$signal" -k "$grace" "$seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout -s "$signal" -k "$grace" "$seconds" "$@"
    elif command -v perl >/dev/null 2>&1; then
        # CMD gets a process group of its own and the watchdog signals the
        # *group*, which is what `timeout` does without --foreground. Signalling
        # the one process is not enough: `bash -c "exec 3<>…; cat <&3"` leaves
        # `cat` blocked on the read when its bash is killed, orphaned onto init
        # and still holding the write end of the capture pipe — so `$(...)` waits
        # for output from a process nobody is going to kill. That is how
        # complex/test--tunnel-public-bind sat for 21 minutes on one 2-second
        # read. The group goes to the harness's own if setpgid fails, so fall
        # back to the single pid rather than signalling that.
        SIG="$signal" SECS="$seconds" GRACE="$grace" perl -MPOSIX -e '
my $pid = fork();
defined $pid or die "fork: $!\n";
if ($pid == 0) {
    POSIX::setpgid(0, 0);
    exec { $ARGV[0] } @ARGV;
    print STDERR "$ARGV[0]: $!\n";
    POSIX::_exit(127);
}
my $timedout = 0;
my $killed = 0;
# The group first, the bare process only if there is no group of its own
# (setpgid can fail). kill returns how many it signalled, so the fallback needs
# no getpgid — which perl POSIX does not even define, and asking for it took the
# watchdog down with "Undefined subroutine" and left CMD running untimed.
#
# CONT behind the signal, every time. A stopped process does not act on a
# catchable signal until it is continued, so a CMD that someone else stopped —
# or that stopped itself on a terminal the ignores above do not cover — would
# take the TERM pending and keep sitting there, and the deadline would come and
# go with nothing to show for it. SIGKILL needs no help; sending CONT with it
# costs nothing and keeps the two paths the same shape.
my $signal_tree = sub {
    my $sig = shift;
    kill($sig, -$pid) or kill($sig, $pid);
    kill("CONT", -$pid) or kill("CONT", $pid);
};
$SIG{ALRM} = sub {
    if ($timedout) { $killed = 1; $signal_tree->("KILL"); return; }
    $timedout = 1;
    $signal_tree->($ENV{SIG});
    alarm $ENV{GRACE};
};
alarm $ENV{SECS};
waitpid($pid, 0);
alarm 0;
exit(137) if $killed;
exit(124) if $timedout;
exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
' "$@"
    else
        echo "timeout_run: no timeout, gtimeout or perl here." >&2
        return 1
    fi
}

# pty_run [-t SECONDS] LOGFILE CMD... : run CMD on a pty of its own, with the
# typescript in LOGFILE (/dev/null to discard). Exits with CMD's status.
#
# A test needs this when what it measures is the terminal itself — who owns the
# pty a foreground booth starts on, say — which no redirect can fake.
#
# -t takes the deadline here rather than leaving it to the caller: timeout_run
# can only wrap a real command, and the command here is `script`, which only
# pty_run knows how to spell on this OS.
pty_run() {
    local limit=""
    if [[ "${1:-}" == "-t" ]]; then
        limit="$2"; shift 2
    fi
    local log="$1"; shift

    local argv
    if [[ "$HOST_OS" == "MAC" ]]; then
        argv=(script -q -e "$log" "$@")
    else
        argv=(script -qec "$(quote_args "$@")" "$log")
    fi

    if [[ -n "$limit" ]]; then
        timeout_run "$limit" "${argv[@]}"
    else
        "${argv[@]}"
    fi
}

# quote_args CMD... : the arguments as one shell-quotable string, for the tools
# that take a command line rather than an argument vector (util-linux script).
quote_args() {
    local out="" arg
    for arg in "$@"; do
        out+="${out:+ }$(printf '%q' "$arg")"
    done
    printf '%s' "$out"
}

# touch_year_ago PATH... : backdate PATH... by a year, for a test that needs a
# file old enough to look stale (git's gc horizon, a cache's expiry).
touch_year_ago() {
    local stamp
    if stamp=$(date -v-1y +%Y%m%d%H%M 2>/dev/null) && [[ -n "$stamp" ]]; then
        touch -t "$stamp" "$@"          # BSD
    else
        touch -d '1 year ago' "$@"      # GNU
    fi
}

# Clear .booth/.tmp/ between booth runs — the contents, never the directory.
#
# `rm -rf .booth/.tmp` looks equivalent and is not. That directory is a bind
# mount source (booth mounts it writable over the read-only .booth/), and
# deleting it immediately before `docker run` leaves Docker Desktop's file
# sharing holding a stale handle for the path: the -v mount silently does not
# take effect, the container sees the read-only .booth/ underneath instead, and
# the first write inside fails with "Read-only file system". It is a race, so it
# reproduces as an intermittent failure — a 2-second pause between the delete
# and the run is enough to hide it again.
#
# Booth itself never removes this directory: PrepareBoothTmp empties it at start
# and cleanupBoothTmp empties it at exit, both leaving the directory in place.
# Tests should clear it the same way the product does.
#
# Usage (from a test's own project directory):
#     reset_booth_tmp            # ./.booth/.tmp
#     reset_booth_tmp "$DIR"     # $DIR/.booth/.tmp
# ── Picking a port a test can actually bind ──────────────────────────────────
#
# The usual "is this port free?" check looks for a listener, and that misses the
# thing most likely to take a port out from under a test: the kernel. Every
# outbound connection is assigned an ephemeral port, and one sitting in
# ESTABLISHED or TIME_WAIT is invisible to `lsof -sTCP:LISTEN` while still making
# the bind fail. basic/test003 lost a run to exactly that —
#
#   failed to bind host port 127.0.0.1:39386/tcp: address already in use
#
# — on a port the check had just called free.
#
# Two changes fix it. Candidates come from *below* the ephemeral range, so the
# kernel will never hand one out on its own; and a candidate is confirmed by
# binding it rather than by looking for a listener, which is the same question
# docker is about to ask.

# ephemeral_port_floor is the lowest port the kernel assigns on its own.
ephemeral_port_floor() {
  local floor=""

  if [[ -r /proc/sys/net/ipv4/ip_local_port_range ]]; then
    floor=$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || true)
  elif command -v sysctl >/dev/null 2>&1; then
    floor=$(sysctl -n net.inet.ip.portrange.first 2>/dev/null || true)
  fi

  # Linux's default, and below macOS's 49152 — safe either way if the lookup
  # gave us nothing usable.
  case "$floor" in
    ""|*[!0-9]*) floor=32768 ;;
  esac
  echo "$floor"
}

# port_is_bindable reports whether 127.0.0.1:<port> can be bound right now.
port_is_bindable() {
  local port="$1"

  if have_python3; then
    # A bind with no listen and no connect leaves nothing behind when it closes,
    # so asking this question does not itself make the port unavailable.
    if python3 -c '
import socket, sys
sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
' "$port" 2>/dev/null; then
      return 0
    fi
    return 1
  fi

  # No python3: fall back to looking for a listener. Weaker — it cannot see a
  # port held by something that never listened — but picking below the ephemeral
  # range has already ruled out the case that fallback would miss.
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"
  elif command -v nc >/dev/null 2>&1; then
    ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1
  else
    # Git Bash has none of the three, which is where a Windows host lands. Bash
    # asks the same question itself: a connect to 127.0.0.1:<port> that succeeds
    # means something is listening there. The subshell closes the descriptor on
    # its way out, so the probe leaves nothing behind either.
    ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null
  fi
}

# pick_free_port prints a port this host will let the caller bind.
#
# Extra arguments are offsets that must be bindable too, for a test that needs a
# port and something at a fixed distance above it — an expose offset, or room
# for a scan to advance into:
#
#     PORT="$(pick_free_port)"          # just the one
#     PORT="$(pick_free_port 300)"      # PORT and PORT+300
#     PORT="$(pick_free_port 1000 2000)"
#
# The whole span stays below the ephemeral floor, not just its first port.
pick_free_port() {
  local floor low high span port index offset reach ok
  floor=$(ephemeral_port_floor)

  # The furthest above the port itself the caller needs.
  reach=0
  for offset in "$@"; do
    (( offset > reach )) && reach=$offset
  done

  # Above the registered-service crowd, below the ephemeral range.
  low=20000
  high=$((floor - 1 - reach))
  if (( high <= low )); then
    # A host tuned to hand out ephemeral ports from very low down, or a caller
    # reaching so far up that nothing fits underneath. Take the old window
    # rather than nothing, and let the bind check carry it.
    low=30000
    high=$((40000 - reach))
  fi
  span=$((high - low + 1))

  for index in {1..100}; do
    port=$((low + RANDOM % span))
    ok=true
    if ! port_is_bindable "$port"; then
      ok=false
    else
      for offset in "$@"; do
        if ! port_is_bindable $((port + offset)); then
          ok=false
          break
        fi
      done
    fi
    if [[ "$ok" == true ]]; then
      echo "$port"
      return 0
    fi
  done

  echo "Failed to find a free port in $low-$high after 100 tries" >&2
  return 1
}

# pick_free_port_other_than prints a free port that is none of the ports given.
#
# Picking a port does not reserve it, and nothing stops two calls to
# pick_free_port from landing on the same number — so a test that needs two
# ports to differ has to say so. What goes wrong when it does not depends on the
# test: two booths racing for one port, one container asked to publish the same
# host port twice, or a case that quietly proves nothing because the "other"
# port was the same one.
#
#     PORT_A="$(pick_free_port)"
#     PORT_B="$(pick_free_port_other_than "$PORT_A")"
pick_free_port_other_than() {
  local port taken index distinct

  for index in {1..100}; do
    port="$(pick_free_port)" || return 1

    distinct=true
    for taken in "$@"; do
      if [[ "$port" == "$taken" ]]; then
        distinct=false
        break
      fi
    done

    if [[ "$distinct" == true ]]; then
      echo "$port"
      return 0
    fi
  done

  echo "Failed to find a free port distinct from: $*" >&2
  return 1
}

# ── Android emulator tests: capable by default, off by exception ─────────────
#
# These are opt-*out*. A machine that can run them should: a test nobody ever
# turns on is a test nobody notices rotting, and the emulator claims are exactly
# the ones no other test can see — a booth that stops persisting its device fails
# nothing, it just quietly loses the device on every restart.
#
# Booting Android is minutes rather than seconds, so the two places that make it
# a bad trade are named rather than assumed:
#
#   CB_ANDROID_EMULATOR_TEST=1   run it here regardless (what the docs have
#                                always said, and still true)
#   CB_ANDROID_EMULATOR_TEST=0   never run it here
#   unset                        run it when this host can

# can_use_kvm reports whether this host can hardware-accelerate the emulator.
#
# Presence is not enough — /dev/kvm is root:kvm, so a user outside that group
# sees the node and still cannot open it.
can_use_kvm() {
  [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]
}

# android_emulator_test_enabled reports whether an emulator test should run here,
# printing the reason when it should not.
android_emulator_test_enabled() {
  case "${CB_ANDROID_EMULATOR_TEST:-}" in
    1|true|yes|on)
      return 0
      ;;
    0|false|no|off)
      echo "SKIP: CB_ANDROID_EMULATOR_TEST is off." >&2
      return 1
      ;;
  esac

  # CI is the standard signal every runner sets. Checked here rather than in a
  # workflow file so a suite added to CI later is off by default instead of
  # discovering the cost the hard way.
  if [[ -n "${CI:-}" ]]; then
    echo "SKIP: running under CI — set CB_ANDROID_EMULATOR_TEST=1 to run the emulator test here anyway." >&2
    return 1
  fi

  if ! can_use_kvm; then
    echo "SKIP: no usable /dev/kvm — the emulator falls back to software and boots roughly 13x slower. Set CB_ANDROID_EMULATOR_TEST=1 to run anyway." >&2
    return 1
  fi

  return 0
}

reset_booth_tmp() {
  local base="${1:-.}"
  local tmp_dir="${base}/.booth/.tmp"
  [ -d "${base}/.booth" ] || return 0
  mkdir -p "$tmp_dir"
  find "$tmp_dir" -mindepth 1 -delete 2>/dev/null || true
  return 0
}

# Run a booth whose output the test does not assert on — a setup step rather
# than a measurement.
#
# The tempting form is `run_coding_booth … >/dev/null 2>&1`, and it fails badly:
# under `set -euo pipefail` a booth that exits non-zero kills the script on that
# line, with its diagnosis already discarded down /dev/null. What the operator
# sees is every test *before* that point printing ✅ and the script exiting 1 —
# "all tests passed and the test failed" — with no clue which line died.
#
# This reports the failure as a failed test, with the booth's own output, and
# lets the caller decide whether to continue.
#
# Usage:
#     booth_step 4 "booth run with --leave-tmp-on-exit" --leave-tmp-on-exit -- 'cmd' \
#         || FAILED=$((FAILED + 1))
booth_step() {
  local num="$1" desc="$2"
  shift 2
  local out rc=0
  out="$(run_coding_booth "$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    print_test_result "false" "$0" "$num" "$desc (booth exited $rc)"
    printf '%s\n' "$out" | tail -20 | sed 's/^/  /'
    return 1
  fi
  return 0
}

# Opt a test into building against a locally-rebuilt base image instead of the
# upstream nawaman/codingbooth Hub image. Use this when the test triggers a
# Boothfile build that relies on a setup-script fix that hasn't shipped to
# Docker Hub yet (e.g. clang/swift/elm arm64 workarounds).
#
# Why this matters: BuildKit's `# syntax=docker/dockerfile:1.7` frontend
# always resolves a `FROM nawaman/codingbooth:...` tag to the upstream
# registry digest, even when an identically-named image exists locally. Naming
# the local image under a repo that doesn't exist on Docker Hub
# (cb-local/codingbooth) sidesteps that resolution.
#
# Scoping: the export lives in the test script's process; each test is
# launched in a subshell by the suite runner, so the override does NOT leak
# into sibling tests. If a single test needs to revert mid-run (e.g. one
# build step should use the local image and a later one should hit Docker
# Hub), call `restore_default_base_image` between them.
#
# Usage (call once near the top of the test, after `source ../../common--source.sh`):
#   use_local_base_image || exit 0    # skips if local image not present
use_local_base_image() {
  local version="${1:-}"
  if [[ -z "$version" ]]; then
    local booth_path script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    booth_path="$(find_local_booth_build "$script_dir")" || booth_path=""
    if [[ -n "${booth_path:-}" ]]; then
      version=$("$booth_path" version 2>/dev/null | tail -1 | sed 's/.*: //')
    fi
  fi
  [[ -z "$version" || "$version" == "dev" ]] && version="latest"

  local img="cb-local/codingbooth:base-${version}"
  if docker image inspect "$img" >/dev/null 2>&1; then
    export CB_PREBUILD_REPO="cb-local/codingbooth"
    return 0
  fi

  echo "SKIP: ${img} not built locally; tag a rebuilt base image as cb-local/codingbooth:base-${version} to enable this test." >&2
  return 1
}

# Counterpart to use_local_base_image — unsets the env var so subsequent
# booth invocations in the same script fall back to the default Hub repo.
restore_default_base_image() {
  unset CB_PREBUILD_REPO
}

# In-place sed that works on both GNU and BSD.
#
# GNU sed takes `-i` with no argument; BSD/macOS sed requires a suffix and
# otherwise swallows the *script* as the backup extension, then tries to read the
# filename as the script — "sed: 1: \"file\": unterminated substitute pattern",
# exit 1, file untouched. Tests that ignored that exit status went on to assert
# on an edit that never happened. Detected by feature, not by uname, so a GNU sed
# installed on a Mac still takes the GNU branch.
sed_inplace() {
  local script="$1" file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$script" "$file"
  else
    sed -i '' "$script" "$file"
  fi
}

# Architecture the Docker daemon builds for — "amd64" or "arm64" (arm64 is the
# default on Apple Silicon). Browser tests need it because Google publishes no
# linux-arm64 build of Chrome for Testing: on arm64 the selenium and puppeteer
# setups fall back to Debian Bookworm's Chromium, so the browser is in a
# different place even though both setups work. Echoes "" if docker is absent.
docker_server_arch() {
  local arch
  arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null || true)"
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  echo "$arch"
}

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
  COLOR_CMD='\033[1;36m'    # Cyan bold for commands
  COLOR_BOOTH='\033[1;33m'  # Yellow bold for codingbooth
  COLOR_RESET='\033[0m'
else
  COLOR_CMD=''
  COLOR_BOOTH=''
  COLOR_RESET=''
fi

# Emit a command trace to stderr, colorized only when stderr is a terminal.
# The COLOR_* vars above are chosen from stdout, but the trace goes to stderr:
# tests capture it with `2>&1` and drop it with a `^> `-anchored match, which an
# ANSI color prefix would silently defeat.
# Usage: trace_cmd <sgr-code> <text...>
trace_cmd() {
  local sgr="$1"; shift
  if [[ -t 2 ]]; then
    printf '\033[%sm%s\033[0m\n' "$sgr" "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

# Run a command with visible output of what's being executed
# Usage: run_cmd <command...>
# Example: run_cmd ls -la
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
run_cmd() {
  trace_cmd '1;36' "> $*"
  "$@"
}

# Run a codingbooth command with highlighted output
# Usage: run_coding_booth [args...]
# Example: run_coding_booth --variant base -- echo hello
# The path to codingbooth is auto-detected relative to the test script
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
#
# Quoting after `--`: everything after `--` is joined with spaces into ONE shell
# command line and run via `bash -lc` in the container (see docs/BOOTH_RUN.md).
# Argument boundaries do NOT survive that join, so pass the command as a single
# quoted argument:
#
#     run_coding_booth -- 'cowsay hello'                       # ✓
#     run_coding_booth -- 'gem list colorize | grep colorize'  # ✓ (pipeline in container)
#     run_coding_booth -- bash -lc 'cowsay hello'              # ✗ flattens to: bash -lc cowsay hello
#
# The third form silently runs `cowsay` with $0="hello" instead of failing loudly,
# which is how it went unnoticed in 19 tests. There is no need to add your own
# `bash -lc` — the wrapper already supplies a login shell.
run_coding_booth() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

  # The locally built CLI, not the wrapper: this helper injects --version for a
  # dev build and reads `version` to decide, neither of which means anything for
  # a release binary behind the wrapper.
  local booth_path=""
  if ! booth_path="$(find_local_booth_build "$script_dir")"; then
    echo "ERROR: Could not find codingbooth" >&2
    return 1
  fi

  # When running a dev build, default to --version latest so prebuilt images resolve.
  # Only inject for run-like invocations, not for subcommands like list/start/stop/etc.
  local version_args=()
  local cb_version
  cb_version=$("$booth_path" version 2>/dev/null | tail -1 | sed 's/.*: //')
  if [[ "$cb_version" == "dev" ]]; then
    # Check if the first arg is a non-run subcommand — skip --version injection for those
    local first_arg="${1:-}"
    local is_subcommand=false
    case "$first_arg" in
      list|start|stop|restart|remove|prune|logs|shell|exec|cp|inspect|stats|top|diff|wait|expose|home-volume-list|home-volume-export|home-volume-import|message|example|template|config|build|express|version|help|--help|-h|print-security-warning)
        is_subcommand=true ;;
    esac

    if [[ "$is_subcommand" == false ]]; then
      # Only inject if the caller didn't already pass --version (before --)
      local has_version=false
      for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then break; fi
        if [[ "$arg" == "--version" ]]; then has_version=true; break; fi
      done
      if [[ "$has_version" == false ]]; then
        version_args=(--version latest)
      fi
    fi
  fi

  trace_cmd '1;33' "> codingbooth $*"

  # Container paths in the booth's own command have to survive this shell.
  # Git Bash rewrites an argument that looks like a Unix absolute path into a
  # Windows one, which is what makes `--code /tmp/x` reach the engine as
  # `C:/Users/.../Temp/x` — and what turned
  #
  #     run_coding_booth -- ls /usr/local/bin/kubectx
  #
  # into `ls C:/Program Files/Git/usr/local/bin/kubectx`, so the test saw no
  # output and blamed the setup. MSYS2_ARG_CONV_EXCL names prefixes to leave
  # alone: the roots below exist only inside a booth, never as a host path a
  # test would pass (a host path here is /c/… or /tmp/…). /tmp is deliberately
  # absent — it is both, so a test that means the booth's /tmp says so itself,
  # per command, as basic/test008 does. A caller's own value is kept.
  #
  # Set for the booth command only, not exported into the rest of the test.
  local conv_excl="/usr;/opt;/etc;/var;/srv;/root;/home/coder;/bin;/sbin;/lib;/lib64;/dev;/proc;/sys;/booth;/workspace"
  if [[ -n "${MSYS2_ARG_CONV_EXCL:-}" ]]; then
    conv_excl="${MSYS2_ARG_CONV_EXCL};${conv_excl}"
  fi

  # Optional forensics (CB_DIAG_LOG). Tests capture booth with `2>/dev/null`, so a
  # run that intermittently produces nothing leaves no evidence of why — the test
  # either sees an empty string or, with no `||` guard, `set -e` kills the script
  # and the suite prints `FAILED:` with no output at all. When CB_DIAG_LOG is set,
  # record the command, its exit code, and a copy of stderr the caller's redirect
  # cannot reach.
  #
  # Deliberately leaves stdout ALONE. Buffering booth's stdout through a variable
  # or a process substitution can itself truncate or drop output, which is the very
  # symptom being investigated — a diagnostic that can cause the bug it is hunting
  # is worse than none. Only stderr is teed, so the worst case is a few missing log
  # lines, never missing test data.
  # stderr goes through a temp file rather than `2> >(tee ...)`. Process
  # substitution opens /dev/fd/N, which a sandboxed run cannot read, so the
  # tee form failed the call outright — a diagnostic that breaks the command
  # it is tracing. The temp file buffers stderr until the command exits
  # instead of streaming it; the log content is identical either way.
  if [[ -n "${CB_DIAG_LOG:-}" ]]; then
    local _rc=0 _errfile
    _errfile=$(mktemp "${TMPDIR:-/tmp}/cb-diag-stderr.XXXXXX")
    printf '%s  === codingbooth %s\n' "$(date '+%H:%M:%S')" "$*" >>"$CB_DIAG_LOG"
    MSYS2_ARG_CONV_EXCL="$conv_excl" "$booth_path" ${version_args[@]+"${version_args[@]}"} "$@" \
      2>"$_errfile" || _rc=$?
    cat "$_errfile" >>"$CB_DIAG_LOG"
    cat "$_errfile" >&2
    rm -f "$_errfile"
    printf '%s  --- rc=%s\n' "$(date '+%H:%M:%S')" "$_rc" >>"$CB_DIAG_LOG"
    return $_rc
  fi

  # Safe expansion: avoids "unbound variable" under `set -u` with Bash 3.2 when the array is empty.
  MSYS2_ARG_CONV_EXCL="$conv_excl" "$booth_path" ${version_args[@]+"${version_args[@]}"} "$@"
}

# ── Container paths survive the shell (Windows) ──────────────────────────────
#
# Git Bash rewrites an argument that looks like a Unix absolute path into a
# Windows one before the program sees it. That is right for a Windows program
# being handed a host path — it is how `booth --code /tmp/x` reaches docker as
# `C:/Users/.../Temp/x` — and wrong for every path that belongs to the
# *container*:
#
#     docker exec -u coder "$NAME" cat /home/coder/code/file
#     cat: 'C:/Program Files/Git/home/coder/code/file': No such file or directory
#
# `docker exec` takes no host paths at all, and the host paths of `docker run`
# and `docker create` (a -v source) are understood by Docker Desktop in the
# shell's own `/c/Users/...` form, so for those subcommands the rewriting is
# pure loss. MSYS_NO_PATHCONV
# turns it off, and wrapping docker here rather than at each call site covers
# every test that sources this file without touching one of them.
#
# Not for the others: `docker build -f <path>` and `docker cp`'s host side are
# resolved by the CLI itself, locally, where a `/c/Users/...` path is not one.
#
# Defined only when there is a real docker to wrap, so `command -v docker` still
# answers "no docker here" on a host without one — several tests skip on exactly
# that. A test that wants the binary's own path must ask `type -P docker`:
# `command -v` would name this function instead.
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && type -P docker >/dev/null 2>&1; then
    docker() {
        case "${1:-}" in
            exec|run|create) MSYS_NO_PATHCONV=1 command docker "$@" ;;
            *)        command docker "$@" ;;
        esac
    }
    export -f docker
fi

# ── What this host can and cannot do ─────────────────────────────────────────
#
# The helpers below answer that, so a test does not assume the host is the one
# it was written on. The suites run on Linux, macOS and Windows (Git Bash) —
# booth is installed on all three — and each of these marks a place where one
# of them cannot do what a test took for granted: hold a port open, keep a
# permission bit, make a symlink, run an MSYS tool off a stubbed PATH, resolve
# a Unix path. See also have_python3 above, the GNU-tool shims, and
# tests/README.md.

# occupy_port holds a port open for a while, for a case about what booth does
# when a port is taken. It prints the PID of the holder, which the caller kills
# when it is done, and returns 1 when this host has nothing that can listen —
# the case then has to skip rather than assert on a port nobody is holding.
#
#     BUSY_PID="$(occupy_port "$port" 30)" || { echo "SKIP: ..."; exit 0; }
#     # it returns as soon as the holder is started, so wait for the port to answer
#     for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 0.1; done
#     ...
#     kill "$BUSY_PID" 2>/dev/null || true
#
# python3 where it is real (see have_python3), else PowerShell, which a Windows
# host always has and which is the only listener Git Bash can reach: it ships no
# nc, and bash itself cannot listen, only connect.
occupy_port() {
  local port="$1" seconds="${2:-30}"
  if have_python3; then
    # Both streams to /dev/null, or the holder keeps the caller's command
    # substitution open — PID="$(occupy_port …)" would wait out the whole
    # sleep instead of returning the PID.
    python3 -c "
import socket, sys, time
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('127.0.0.1', int(sys.argv[1])))
sock.listen()
time.sleep(float(sys.argv[2]))
" "$port" "$seconds" >/dev/null 2>&1 &
    echo $!
    return 0
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "
\$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $port)
\$listener.Start()
Start-Sleep -Seconds $seconds
\$listener.Stop()" >/dev/null 2>&1 &
    echo $!
    return 0
  fi
  return 1
}

# have_symlinks reports whether this host makes real symbolic links, for a case
# about what a script does when it finds one. Under Git Bash `ln -s` copies the
# file instead unless MSYS was configured for native symlinks — and Windows only
# allows those to an administrator or with Developer Mode on — so the "symlink"
# a test laid down would be an ordinary file, and the case would quietly assert
# the opposite of what it says. The only honest check is to try one.
have_symlinks() {
  local dir result=1
  dir="$(mktemp -d)" || return 1
  : > "$dir/target"
  ln -s "$dir/target" "$dir/link" 2>/dev/null
  [[ -L "$dir/link" ]] && result=0
  rm -rf "$dir"
  return $result
}

# is_link_or_copy reports whether a script put what it was asked to at path: the
# symlink it made, or — on a host where `ln -s` copies instead (see
# have_symlinks) — the copy that landed there. Insisting on -L there asserts
# what the host can do, not what the script did.
is_link_or_copy() {
  if have_symlinks; then
    [[ -L "$1" ]]
  else
    [[ -e "$1" ]]
  fi
}

# unix_modes reports whether a file's permission bits mean what they say on this
# host, so a case about 0600 or the exec bit can say what it is doing:
#
#     if unix_modes; then
#       check 4 "init: keeps the staged file's mode" "600" "$(stat -c '%a' "$file")"
#     fi
#
# Windows has no permission bits. `chmod` there sets a read-only flag at best,
# a mode read back is whatever MSYS chooses to report (0644 for a plain file),
# and `chmod +x` on an empty file does not even make it executable — MSYS reads
# executability off the content, so a shebang or a PE header is what counts.
# This is the shell side of cli/src/internal/hostskip, which the Go tests use
# for the same reason.
unix_modes() { [[ "$HOST_OS" != "WIN" ]]; }

# utf8_locale prints a UTF-8 locale this host actually has, for the one kind of
# command that needs one: GNU grep refuses `-P` unless the locale is unibyte or
# UTF-8, and several product scripts read a version with `grep -oP`. Returns 1
# when the host has none, so the caller can skip rather than run a script that
# will die on its first version probe.
#
#     LANG="$(utf8_locale)" bash "$SETUPS/x--install.sh"     # or skip
#
# Deliberately *not* exported for the whole suite, and do not be tempted: MSYS
# grep in a UTF-8 locale cannot match a character outside the BMP, so a UTF-8
# LANG makes every emoji assertion silently stop matching while ASCII ones keep
# working — dryrun/test031 grepped for "📦 Running booth in daemon mode" and went
# red for exactly that reason, on a line that was right there in the output.
# With no LANG, MSYS grep compares bytes and the emoji matches.
#
# Not exporting one is not enough, though: mintty, Git Bash's own terminal, sets
# a UTF-8 LANG itself, so a suite started from it inherits one anyway. Match on
# the text beside an emoji (or any non-BMP character), never the emoji itself.
utf8_locale() {
  local candidate available
  available="$(locale -a 2>/dev/null || true)"
  for candidate in C.utf8 C.UTF-8 en_US.utf8 en_US.UTF-8; do
    if printf '%s\n' "$available" | grep -qix -- "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# ── A script written for the image, run on this host ─────────────────────────
#
# The setups suite runs real setup and launcher scripts on the host with their
# tools stubbed, which is what makes it fast and image-free. Those scripts are
# written for the one place they ever run — the image: Ubuntu, bash 5, GNU
# userland — and a handful of them use something a macOS host has not got:
# `${x,,}`, mapfile, `sed -i` with no suffix, `find -printf`, `stat -c`,
# `grep -P`. The script is not wrong, and rewriting shipped container code so a
# BSD host can run it would be churn for no gain, so the test asks the host
# first and skips. Linux keeps the coverage, which is where CI runs it.
#
#     require_host_tools "booth--file-sync lists its staged files with find -printf" \
#                        gnu-find gnu-stat
#
# Each feature is probed, never version-tested, so a Mac carrying Homebrew's
# coreutils/gnu-sed takes the real branch and runs the case for real. See also
# sed_inplace, which shims the one GNU-ism the tests themselves need, and
# test--desktop-start-ports.sh, which probes the bash its *subject* will get
# rather than the one running the test.
#
# missing_host_tools prints the named features this host lacks, "" when it has
# them all. require_host_tools is the guard built on it: it prints the SKIP line
# and exits the test, so it reads as one statement at the top of a file.
missing_host_tools() {
  local feature label missing=""
  for feature in "$@"; do
    case "$feature" in
      bash4)    label="bash 4 (\${x,,}, mapfile)"
                bash -c 'x=A; : "${x,,}"; mapfile -t _ </dev/null' ;;
      gnu-sed)  label="GNU sed"
                sed --version ;;
      gnu-find) label="GNU find (-printf)"
                find . -maxdepth 0 -printf '' ;;
      gnu-stat) label="GNU stat (-c)"
                stat -c '%a' . ;;
      grep-P)   label="grep -P"
                printf 'a1\n' | grep -qP '\d' ;;
      *)        label="$feature"
                echo "missing_host_tools: unknown feature \"$feature\"" >&2
                false ;;
    esac >/dev/null 2>&1 || missing+="${missing:+, }$label"
  done
  printf '%s' "$missing"
}

require_host_tools() {
  local subject="$1"; shift
  local missing
  missing="$(missing_host_tools "$@")"
  [[ -z "$missing" ]] && return 0
  echo "SKIP: $subject, and this host has no $missing (bash ${BASH_VERSION%%(*} on $(uname -s))"
  exit 0
}

# stub_path assembles the PATH for a setup script run against stubbed tools:
# the given directories, and on Windows the one directory a stub cannot do
# without.
#
#     OUT=$(env -i EUID=0 PATH="$(stub_path "$STUB/bin")" bash "$SETUPS/x--setup.sh")
#
# A setups test hands the script a PATH holding nothing but what it wants the
# script to find, which is how the guard branches ("skips without XFCE") are
# reached at all. On Linux and macOS that is the whole story. Under Git Bash it
# is not: every tool in /usr/bin is an MSYS program that loads msys-2.0.dll, and
# Windows resolves a program's DLLs through PATH — so `basename` copied into a
# stub directory and run with `env -i PATH=<stub>` dies on
#
#     error while loading shared libraries: ?: cannot open shared object file
#
# before it can do anything, and every case in the file fails on its first line
# of setup. /usr/bin goes on the *end*, after the stubs, so a tool the test put
# there still wins and anything the test wanted missing (xfce4-session, i3,
# apt-get) stays missing — none of them is a thing Git Bash ships.
stub_path() {
  local path
  path="$(IFS=:; echo "$*")"
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    path="$path:$(dirname "$(command -v bash)")"
  fi
  echo "$path"
}

# host_path prints an existing directory the way the host's container engine
# expects to be handed it: unchanged on Linux and macOS, and in Windows form
# ("C:/Users/...") under Git Bash, where a source written the shell's way
# ("/c/Users/...", "/tmp/...") is not a path Windows itself can resolve — booth
# stats a mount source and drops the mount when it is missing, so such a path
# never reaches docker at all.
#
#     mkdir -p "$TMP/data"
#     run-args = ["-v", "$(host_path "$TMP/data"):/data"]
host_path() {
  local dir="$1"
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    (cd "$dir" && pwd -W)
  else
    (cd "$dir" && pwd)
  fi
}

# booth_script_name is the name booth will call itself by in its own output:
# the basename of the binary a test actually ran (ScriptName in the CLI, which
# is filepath.Base(os.Args[0])).
#
# It is `codingbooth` on Linux and macOS and `codingbooth.exe` on Windows, where
# `cli-build.sh` writes the host build. A dryrun expectation that spells it out
# is therefore wrong on one platform or the other — it reaches the booth as
# BOOTH_SCRIPT_NAME, and the "To open an interactive shell instead" hint prints
# it. Use this instead of the literal:
#
#     SCRIPT_NAME="$(booth_script_name)"
booth_script_name() {
  local script_dir booth_path
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  if booth_path="$(find_local_booth_build "$script_dir")"; then
    basename "$booth_path"
  else
    echo "codingbooth"
  fi
}

# Get the version reported by the booth binary itself, so tests stay correct
# even when version.txt has been bumped but the binary hasn't been rebuilt yet.
get_booth_version() {
  run_coding_booth version 2>/dev/null | tail -1 | sed 's/.*: //'
}

# capture_codingbooth: run codingbooth, capture stdout, retry once on
# empty/failed output. Useful inside full-suite runs where rapid container
# spin-up/down occasionally produces a transient empty result that succeeds
# on retry. Pass shell pipeline transforms via $1 (e.g. "head -1", "tail -1").
# Defaults to "cat".
#
# The transform is applied to booth's *captured* output, never to a live pipe —
# see the note at the capture below. Callers writing their own capture should do
# the same: `X=$(run_coding_booth …)` first, then trim, rather than
# `X=$(run_coding_booth … | head -1)`.
#
# Stderr is discarded by default. Set CB_STDERR_LOG to a writable file path to
# append it instead — worth doing for tests whose booth run includes an image
# build, since a build failure otherwise leaves no trace of *why* it failed.
# Each attempt is preceded by a marker line so the two retries stay separable.
# The caller is responsible for creating the log's parent directory.
#
# Booth is given /dev/null on stdin. A capture reads booth's output and never
# writes to it, and booth passes `-i` to `docker run` whenever stdin is open —
# so on a terminal the container's stdin is the suite's own terminal. That costs
# twice over: the container swallows whatever the operator types at the running
# suite, and if anything has put the call in a background process group, docker's
# read of the terminal stops it (see timeout_run). test-boothfile-superfile
# already spelled `</dev/null` into its *container* command to keep a TUI off the
# terminal; this is the same fix, one level up, for every caller.
#
# Usage:
#   ACTUAL=$(capture_codingbooth "head -1" --silence-build -- gcc --version)
capture_codingbooth() {
  local pipeline="${1:-cat}"
  shift
  local errdest="${CB_STDERR_LOG:-/dev/null}"
  local out

  _capture_attempt() {
    local n="$1"; shift
    if [[ "$errdest" != "/dev/null" ]]; then
      echo "=== capture_codingbooth attempt ${n}: codingbooth $* ===" >>"$errdest"
    fi
  }

  # Capture booth's output in full, THEN apply the pipeline to the captured text.
  # Never pipe booth straight into "$pipeline": an early-exiting consumer such as
  # `head -1` closes the pipe as soon as it has its line, booth takes SIGPIPE, and
  # under `set -o pipefail` the whole capture collapses to "". That race is timing
  # dependent, so it only fires on a loaded machine — the failure then looks like
  # flakiness and the retry below hides it instead of fixing it.
  _capture_attempt 1 "$@"
  out=$(run_coding_booth "$@" 2>>"$errdest" </dev/null) || out=""
  out=$(printf '%s\n' "$out" | eval "$pipeline")
  if [[ -z "$out" ]]; then
    sleep 2
    _capture_attempt 2 "$@"
    out=$(run_coding_booth "$@" 2>>"$errdest" </dev/null) || out=""
    out=$(printf '%s\n' "$out" | eval "$pipeline")
  fi
  printf '%s\n' "$out"
}

# Normalize output for cross-platform comparison
# - Strips .exe extension from binary name
# - Converts Windows backslashes to forward slashes
# - Removes single quotes around Windows paths in -v mounts
# - Normalizes MSYS paths (/c/Users → C:/Users)
# - Masks UID/GID values to XXXXX for environment independence
# - Masks BOOTH_HOST_IP, which is whatever address the host running the test has
normalize_output() {
    sed -E \
        -e 's/workspace\.exe/workspace/g' \
        -e 's|\\|/|g' \
        -e "s|-v '([^']+)'|-v \1|g" \
        -e 's|/c/|C:/|gi' \
        -e 's|/C/|C:/|g' \
        -e "s/HOST_UID=[0-9]+/HOST_UID=XXXXX/g" \
        -e "s/HOST_GID=[0-9]+/HOST_GID=XXXXX/g" \
        -e "s/HOST_UID:[[:space:]]+[0-9]+/HOST_UID:       XXXXX/g" \
        -e "s/HOST_GID:[[:space:]]+[0-9]+/HOST_GID:       XXXXX/g" \
        -e "s/BOOTH_HOST_IP=[0-9.]+/BOOTH_HOST_IP=XXXXX/g" \
        -e "s/cb\.created-at=[0-9T:-]+Z/cb.created-at=XXXXX/g"
}

script_relative_path() {
  local script_abs="${1:-$0}"
  local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  script_abs=$(realpath "$script_abs")
  root=$(realpath "$root")
  echo "${script_abs#${root}/tests/}"
}

# Print standardized test result
# Usage: print_test_result <success> <script_path> <test_number> <description>
#   success: "true" or "false"
#   script_path: path to test script (usually $0)
#   test_number: test number
#   description: test description
print_test_result() {
  local success="$1"
  local script_path="$2"
  local test_number="$3"
  local description="$4"
  
  local relative_path=$(script_relative_path "$script_path")
  local icon="✅"
  
  if [[ "$success" != "true" ]]; then
    icon="❌"
  fi
  
  echo "${icon} ${relative_path}: Test ${test_number}: ${description}"
}
