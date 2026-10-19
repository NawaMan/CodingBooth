#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# cb-check-tar-extract.sh — returns 0 when `tar -x` works here, 1 (with an explanation on stderr)
# when it does not. Call it before a setup extracts a tarball, so a broken tar fails with one
# clear message instead of a "Function not implemented" line for every file in the archive.
#
# The known cause is Docker Desktop's Rosetta amd64 emulation on Apple Silicon: Ubuntu's security-patched
# tar (the CVE-2026-5704 fix; seen with 1.35+dfsg-4ubuntu0.4) extracts through openat2(2), which
# Rosetta does not implement, and tar has no fallback. QEMU emulation and native builds
# (including CI) are not affected.

WORK_DIR="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/src" "$WORK_DIR/out"
echo ok > "$WORK_DIR/src/probe"
if tar -cf "$WORK_DIR/probe.tar" -C "$WORK_DIR" src 2>/dev/null \
   && tar -xf "$WORK_DIR/probe.tar" -C "$WORK_DIR/out" 2>/dev/null \
   && [[ -f "$WORK_DIR/out/src/probe" ]]; then
  exit 0
fi

# openat2 is syscall 437 and ENOSYS is errno 38 on x86_64 and arm64 alike; ENOSYS means the
# kernel (or the CPU translator standing in for it) does not provide it. The path must be a
# variable: perl's syscall() refuses a string literal ("Modification of a read-only value").
openat2_enosys=false
if command -v perl >/dev/null 2>&1 \
   && perl -e 'my $p = "/"; my $h = "\0" x 24; my $r = syscall(437, -100, $p, $h, 24);
               exit(($r == -1 && $! + 0 == 38) ? 0 : 1)' 2>/dev/null; then
  openat2_enosys=true
fi

if [[ "$openat2_enosys" == "true" ]]; then
  cat >&2 <<'EOF'
❌ tar cannot extract files in this container: the openat2 system call is not implemented.

   This is Docker Desktop's Rosetta amd64 emulation on Apple Silicon. Ubuntu's tar extracts
   through openat2, which Rosetta does not provide, so every tarball install fails.

   Fix: Docker Desktop → Settings → General → turn OFF "Use Rosetta for x86_64/amd64
   emulation on Apple Silicon", then Apply & restart and build again (QEMU emulation is
   used instead). Native amd64 hosts and arm64 booths are not affected.
EOF
else
  echo "❌ tar cannot extract files in this container (a test extraction failed): $(uname -m), $(tar --version 2>/dev/null | head -1)" >&2
fi
exit 1
