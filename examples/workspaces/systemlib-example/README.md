# System Library Example — link checker in C++

This example is a small C++ link checker that links two real system libraries — libcurl and SQLite — installed with `apt`. `src/linkcheck.cpp` reads a list of URLs, checks each one with libcurl (following redirects and classifying ALIVE/DEAD), records the URL, timestamp, and status into a SQLite database, then reads the rows back. Precise version compatibility: it depends on real system libraries whose development headers and shared objects must both be present and matched for CMake's `find_package` to configure and link. This is the honest version of C/C++ dependency pain — the `libxxx-dev` dance where a missing header or mismatched `.so` breaks the build in ways that have nothing to do with your code. In a booth it's declared once, snapshot-pinned so the exact library versions install every time, and nothing lands on your host — the linking headache becomes a one-line, reproducible detail.

This is the honest version of the "dependency" pain. The hard part of C/C++ isn't the
compiler — it's the `libxxx-dev` dance: installing the right development packages so the
headers *and* the shared objects are present, and getting CMake to find and link them. In
a booth that's declared once and baked into the image; nothing lands on your host.

**Stack:** Clang/LLVM 18, CMake, Make · `libcurl4-openssl-dev`, `libsqlite3-dev`

## Run

```bash
./booth -- ./run-linkcheck.sh
```

That builds and runs in one step. The two halves are also split out, so you can build
once and run repeatedly:

```bash
./booth -- ./build.sh                 # configure + compile into ./build/linkcheck
./booth -- ./run.sh                   # build (incrementally) + run against urls.txt
./booth -- ./run.sh my-urls.txt out.db
```

CMake resolves libcurl and SQLite via `find_package`, builds `linkcheck`, and runs it
against `urls.txt`. Output looks like:

```
Checking 6 URLs...

URL                                              RESULT STATUS
------------------------------------------------ ------ ------
https://example.com/                             ALIVE  200
https://www.iana.org/                            ALIVE  200
https://www.google.com/                          ALIVE  200
https://httpstat.us/404                          DEAD   DEAD: HTTP 404
https://httpstat.us/500                          DEAD   DEAD: HTTP 500
https://this-host-does-not-exist-9x8y7z.invalid/ DEAD   DEAD: Could not resolve host: ...

Summary: 3 alive, 3 dead. Recorded 6 rows to linkcheck.db
```

Every run appends a fresh batch of rows (each stamped with the same UTC time), so the
database accumulates a history of checks. Point it at your own list:

```bash
./booth -- ./run-linkcheck.sh my-urls.txt my-results.db
```

## Inspect the database

`check.sh` prints everything recorded so far — the rows plus a per-status summary:

```bash
./booth -- ./check.sh              # reads linkcheck.db
./booth -- ./check.sh my.db        # or another database file
```

```
=== Recorded checks in linkcheck.db ===
id  checked_at            status                            url
--  --------------------  --------------------------------  ------------------------------
1   2026-07-23T02:14:07Z  DEAD: Couldn't resolve host name  https://example.com/
2   2026-07-23T02:14:07Z  200                               https://www.iana.org/
...

=== Summary by status ===
status                            count
--------------------------------  -----
200                               2
DEAD: Couldn't resolve host name  2
DEAD: HTTP 404                     1
```

The `sqlite3` CLI is installed too, so you can also query the results directly:

```bash
./booth -- sqlite3 linkcheck.db 'SELECT checked_at, status, url FROM checks ORDER BY id DESC LIMIT 10;'
```

## How it works

- `.booth/Boothfile` — Clang + CMake + Make, then
  `install apt libcurl4-openssl-dev libsqlite3-dev sqlite3 ca-certificates`. `APT_SNAPSHOT`
  pins the apt packages so the same library versions are installed every build.
- `CMakeLists.txt` — `find_package(CURL)` and `find_package(SQLite3)` locate the headers and
  shared objects; the target links `CURL::libcurl` and `SQLite::SQLite3`. Missing a `-dev`
  package makes *configure* fail loudly, right where the problem is.
- `src/linkcheck.cpp` — reads `urls.txt`, checks each URL with libcurl (follows redirects,
  5s connect / 15s total timeout), classifies it ALIVE/DEAD, and writes `(url, checked_at,
  status)` into SQLite — then reads the rows back to prove the round-trip.

A link is **DEAD** when libcurl can't complete the request (DNS, connection, or timeout) or
the final HTTP status is `>= 400`; otherwise it's **ALIVE**.

> Needs outbound network to reach the URLs. Demo only — no retries, no concurrency, no
> auth; the checker follows redirects and reports the final status.
