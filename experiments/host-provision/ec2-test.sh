#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# -----------------------------------------------------------------------------
# ec2-test.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Tests `booth prepare ubuntu` on real Ubuntu 26.04 machines: one fresh EC2
# instance per example, all in parallel. On each one, as the AMI's own sudo user
# (ubuntu), with the binary ./build/cli-build.sh made (the kit is embedded):
#   1. `booth prepare ubuntu --yes` in a copy of the example;
#   2. in a NEW ssh session (a fresh login): CB_TARGET=host, then
#      check-example.sh, which runs the example's own in-booth tests.
#
# Usage:  ec2-test.sh [example ...]       default: go-example zig-example
#         ec2-test.sh --sweep             remove EVERY resource this test tagged
# Output: experiments/host-provision/.out/ec2-<example>/
# Exits 1 when any check fails, or when a resource of this run is left behind.
#
# Env:    CB_EC2_TYPE      instance type        (default t3.large)
#         CB_EC2_DISK_GB   root disk size       (default 30)
#         CB_EC2_TTL_MIN   self-destruct after  (default 90 minutes; logins stop 5
#                          minutes before, so keep it 5+ minutes above a run's length)
#         CB_EC2_KEEP=1    leave the instances up for a look (still self-destruct)
#         AWS_REGION / AWS_PROFILE, as the aws CLI reads them
#
# Cleanup, in layers -- an instance must never outlive the test for long:
#   - every resource carries the tags cb-test=host-provision and cb-run=<id>;
#   - a trap on EXIT/INT/TERM/HUP terminates this run's instances, waits until
#     they are terminated, then deletes this run's key pair and security group;
#   - each instance starts with shutdown behaviour "terminate" and schedules
#     `shutdown -h +$CB_EC2_TTL_MIN` at boot, so it deletes itself even when
#     this machine dies mid-run (its disk has DeleteOnTermination);
#   - a run starts by sweeping what earlier runs left: instances launched more
#     than TTL+30 minutes ago, and key pairs / security groups of runs started
#     over 30 minutes ago that have no live instance (so two runs at once leave
#     each other alone); --sweep removes everything tagged, no age limit;
#   - a run ends by listing what is still tagged with its id: anything left
#     fails the run and is named.
# Ctrl-C in a terminal runs the cleanup. A script started as a background job
# (`… &`) has SIGINT ignored from birth and cannot trap it: stop it with kill
# (SIGTERM), which runs the same cleanup.
# -----------------------------------------------------------------------------

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BIN="$REPO/bin/codingbooth-linux-amd64"

TAG_KEY=cb-test
TAG_VAL=host-provision
TYPE="${CB_EC2_TYPE:-t3.large}"
DISK_GB="${CB_EC2_DISK_GB:-30}"
TTL_MIN="${CB_EC2_TTL_MIN:-90}"
AMI_PARAM=/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id

log() { echo "[ec2] $*"; }
die() { echo "[ec2] ERROR: $*" >&2; exit 1; }

command -v aws  >/dev/null || die "aws CLI is not installed"
command -v ssh  >/dev/null || die "ssh is not installed"
command -v curl >/dev/null || die "curl is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || die "aws CLI has no working credentials (aws configure / AWS_PROFILE)"

# ─── Sweep: what is tagged, and removing it ─────────────────────────────────

# live_instances [run-id]: ids of tagged instances not yet terminated.
live_instances() {
  local filters=(Name=tag:$TAG_KEY,Values=$TAG_VAL Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down)
  [ -n "${1:-}" ] && filters+=(Name=tag:cb-run,Values="$1")
  aws ec2 describe-instances --filters "${filters[@]}" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

# terminate_and_wait <id...>
terminate_and_wait() {
  [ "$#" -gt 0 ] || return 0
  log "terminating $*"
  aws ec2 terminate-instances --instance-ids "$@" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "$@" \
    || { sleep 30; aws ec2 wait instance-terminated --instance-ids "$@"; }
}

# delete_sg <id>: retried, since a group stays in use for a while after its
# instance is terminated (the network interface detaches late).
delete_sg() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    aws ec2 delete-security-group --group-id "$1" >/dev/null 2>&1 && { log "deleted security group $1"; return 0; }
    sleep 15
  done
  echo "[ec2] could not delete security group $1" >&2
  return 1
}

# cleanup_run <run-id>: everything of one run.
cleanup_run() {
  local run="$1" ids sg key
  read -ra ids <<< "$(live_instances "$run")"
  terminate_and_wait "${ids[@]}"
  for key in $(aws ec2 describe-key-pairs --filters Name=tag:$TAG_KEY,Values=$TAG_VAL Name=tag:cb-run,Values="$run" \
                 --query 'KeyPairs[].KeyName' --output text 2>/dev/null); do
    aws ec2 delete-key-pair --key-name "$key" >/dev/null && log "deleted key pair $key"
  done
  for sg in $(aws ec2 describe-security-groups --filters Name=tag:$TAG_KEY,Values=$TAG_VAL Name=tag:cb-run,Values="$run" \
                --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do
    delete_sg "$sg"
  done
}

# sweep all|stale: all = every tagged resource; stale = instances older than
# TTL+30 minutes, and key pairs / groups whose run has no live instance.
sweep() {
  local mode="$1" cutoff ids runs run
  if [ "$mode" = all ]; then
    read -ra ids <<< "$(live_instances)"
  else
    cutoff="$(date -u -d "-$((TTL_MIN + 30)) minutes" +%Y-%m-%dT%H:%M:%S)"
    read -ra ids <<< "$(aws ec2 describe-instances \
      --filters Name=tag:$TAG_KEY,Values=$TAG_VAL Name=instance-state-name,Values=pending,running,stopping,stopped \
      --query "Reservations[].Instances[?LaunchTime<'$cutoff'].InstanceId" --output text)"
  fi
  terminate_and_wait "${ids[@]}"
  runs="$( { aws ec2 describe-key-pairs --filters Name=tag:$TAG_KEY,Values=$TAG_VAL \
               --query 'KeyPairs[].Tags[?Key==`cb-run`].Value' --output text
             aws ec2 describe-security-groups --filters Name=tag:$TAG_KEY,Values=$TAG_VAL \
               --query 'SecurityGroups[].Tags[?Key==`cb-run`].Value' --output text; } 2>/dev/null | tr '\t' '\n' | sort -u)"
  for run in $runs; do
    # A run id starts with its UTC start time. A run younger than 30 minutes may
    # be between making its key and launching its instance: not ours to touch.
    if [ "$mode" != all ]; then
      [[ "$run" =~ ^([0-9]{8})-([0-9]{2})([0-9]{2})([0-9]{2})- ]] || continue
      local started
      started="$(date -u -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s 2>/dev/null)" || continue
      [ $(( $(date -u +%s) - started )) -gt 1800 ] || continue
    fi
    [ -z "$(live_instances "$run")" ] || continue      # a run still going: not ours to touch
    log "sweeping leftovers of run $run"
    cleanup_run "$run"
  done
}

# leftovers <run-id>: one line per resource of the run still present.
leftovers() {
  local run="$1"
  aws ec2 describe-instances --filters Name=tag:cb-run,Values="$run" \
    Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d; s/^/instance /'
  aws ec2 describe-key-pairs --filters Name=tag:cb-run,Values="$run" \
    --query 'KeyPairs[].KeyName' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d; s/^/key-pair /'
  aws ec2 describe-security-groups --filters Name=tag:cb-run,Values="$run" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d; s/^/security-group /'
}

if [ "${1:-}" = "--sweep" ]; then
  sweep all
  left="$( { live_instances
             aws ec2 describe-key-pairs --filters Name=tag:$TAG_KEY,Values=$TAG_VAL --query 'KeyPairs[].KeyName' --output text
             aws ec2 describe-security-groups --filters Name=tag:$TAG_KEY,Values=$TAG_VAL --query 'SecurityGroups[].GroupId' --output text
           } 2>/dev/null | tr '\t' '\n' | sed '/^$/d')"
  [ -z "$left" ] || die "still tagged after the sweep: $(echo $left)"
  log "nothing tagged $TAG_KEY=$TAG_VAL is left"
  exit 0
fi

# ─── This run ───────────────────────────────────────────────────────────────

EXAMPLES=("$@")
[ "${#EXAMPLES[@]}" -gt 0 ] || EXAMPLES=(go-example zig-example)
for ex in "${EXAMPLES[@]}"; do
  [ -d "$REPO/examples/booths/$ex" ] || die "no example examples/booths/$ex"
done
[ -x "$BIN" ] || die "$BIN is missing: run ./build/cli-build.sh"

RUN="$(date -u +%Y%m%d-%H%M%S)-$RANDOM"
WORK="$(mktemp -d)"
KEY_NAME="cb-host-provision-$RUN"
SG_ID=""
TAGS="{Key=$TAG_KEY,Value=$TAG_VAL},{Key=cb-run,Value=$RUN}"

CLEANED=0
cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  trap '' INT TERM HUP                                   # finish the cleanup, whatever else arrives
  [ -n "$(jobs -p)" ] && kill $(jobs -p) 2>/dev/null
  if [ "${CB_EC2_KEEP:-}" = 1 ]; then
    log "CB_EC2_KEEP=1: leaving run $RUN up; it self-destructs within $TTL_MIN minutes of boot"
    log "  remove it now with: $0 --sweep"
  else
    log "cleaning up run $RUN"
    cleanup_run "$RUN"
  fi
  rm -rf "$WORK"
}
on_signal() { echo; log "interrupted"; cleanup; exit 130; }
trap cleanup EXIT
trap on_signal INT TERM HUP

log "run $RUN: ${EXAMPLES[*]} on $TYPE in $(aws configure get region 2>/dev/null || echo "${AWS_REGION:-?}")"
sweep stale

# Access: a key for this run only, and ssh from this machine's address only.
ssh-keygen -q -t ed25519 -N '' -C "$KEY_NAME" -f "$WORK/key"
aws ec2 import-key-pair --key-name "$KEY_NAME" --public-key-material "fileb://$WORK/key.pub" \
  --tag-specifications "ResourceType=key-pair,Tags=[$TAGS]" >/dev/null || die "import-key-pair failed"
MY_IP="$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')"
[[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not read this machine's public IPv4 address"
SG_ID="$(aws ec2 create-security-group --group-name "cb-host-provision-$RUN" \
           --description "CodingBooth host-provision test run $RUN" \
           --tag-specifications "ResourceType=security-group,Tags=[$TAGS]" \
           --query GroupId --output text)" || die "create-security-group failed"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP/32" >/dev/null \
  || die "authorize-security-group-ingress failed"

cat > "$WORK/user-data" <<EOF
#!/bin/bash
# Self-destruct: shutdown behaviour is "terminate", so this deletes the instance.
shutdown -h +$TTL_MIN "CodingBooth host-provision test: time is up"
EOF

SSH_OPTS=(-i "$WORK/key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$WORK/known_hosts"
          -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o BatchMode=yes -o LogLevel=ERROR)

# one_example <example>: launch, prepare, check. Writes .out/ec2-<example>/.
one_example() {
  local ex="$1" out="$HERE/.out/ec2-$1" id ip i rc
  rm -rf "$out" && mkdir -p "$out"
  exec > "$out/run.log" 2>&1
  id="$(aws ec2 run-instances --image-id "resolve:ssm:$AMI_PARAM" --instance-type "$TYPE" \
          --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
          --instance-initiated-shutdown-behavior terminate \
          --metadata-options HttpTokens=required \
          --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$DISK_GB,VolumeType=gp3,DeleteOnTermination=true}" \
          --user-data "file://$WORK/user-data" \
          --tag-specifications "ResourceType=instance,Tags=[$TAGS,{Key=Name,Value=cb-host-provision-$ex}]" \
                               "ResourceType=volume,Tags=[$TAGS]" \
          --query 'Instances[0].InstanceId' --output text)" || { echo "FAIL  run-instances"; return 1; }
  echo "instance $id"
  aws ec2 wait instance-running --instance-ids "$id" || { echo "FAIL  instance never ran"; return 1; }
  ip="$(aws ec2 describe-instances --instance-ids "$id" \
          --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
  echo "address $ip"
  for i in $(seq 1 40); do ssh "${SSH_OPTS[@]}" "ubuntu@$ip" true 2>/dev/null && break; sleep 6; done
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'cloud-init status --wait >/dev/null; . /etc/os-release; echo "$PRETTY_NAME"; id' \
    || { echo "FAIL  ssh never came up"; return 1; }

  # The binary, the generic check and the example (files git tracks or would add).
  local stage="$WORK/stage-$ex"; mkdir -p "$stage/project"
  install -m 0755 "$BIN" "$stage/booth"
  install -m 0755 "$HERE/check-example.sh" "$stage/check-example.sh"
  (cd "$REPO/examples/booths/$ex" && git ls-files -co --exclude-standard -z . | tar --null -T - -cf -) \
    | tar -xf - -C "$stage/project"
  tar -cf - -C "$stage" . | ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'tar -xf - -C ~' || { echo "FAIL  copy"; return 1; }

  echo "== booth prepare ubuntu"
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'cd ~/project && ~/booth prepare ubuntu --yes --report ~/report.txt' \
    < /dev/null > "$out/prepare.log" 2>&1; rc=$?
  echo "prepare exit $rc"
  # A new session: a fresh login, as the user's next terminal would be. The
  # script comes on stdin, so nothing in it may read stdin (hence < /dev/null).
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" "bash -s $rc" > "$out/checks.log" 2>&1 <<'EOS'
export REPORT=~/report.txt
touch "$REPORT"
res() { if [ "$2" = 0 ]; then echo "PASS  $1" | tee -a "$REPORT"; else echo "FAIL  $1" | tee -a "$REPORT"; fi; }
res "booth prepare ubuntu exits 0"             "$([ "$1" = 0 ]; echo $?)"
res "the provisioning has no FAIL line"        "$(! grep -q '^FAIL ' "$REPORT"; echo $?)"
res "CB_TARGET=host in a login shell"          "$(bash -lc 'printenv CB_TARGET' | grep -qx host; echo $?)"
res "~/.bashrc has the CodingBooth block"      "$(grep -q 'CodingBooth profile' ~/.bashrc; echo $?)"
cd ~/project && ~/check-example.sh < /dev/null
EOS
  for f in report.txt report-tests.log; do
    ssh "${SSH_OPTS[@]}" "ubuntu@$ip" "cat ~/$f" > "$out/$f" 2>/dev/null
  done
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'cat /tmp/startups.log' > "$out/startups.log" 2>/dev/null
  # The verdict comes from checks.log: every check prints its line there.
  grep -q '^FAIL ' "$out/checks.log" && return 1
  grep -q '^PASS  example: ' "$out/checks.log" || grep -q '^UNTESTED ' "$out/checks.log" || return 1
  grep -q '^== 0 failed check(s)$' "$out/checks.log" || return 1
  return 0
}

declare -A PIDS
for ex in "${EXAMPLES[@]}"; do
  one_example "$ex" & PIDS[$ex]=$!
  log "$ex: launching (log: $HERE/.out/ec2-$ex/run.log)"
done

FAILED=()
for ex in "${EXAMPLES[@]}"; do
  if wait "${PIDS[$ex]}"; then
    log "$ex: PASS"
  else
    log "$ex: FAIL"
    FAILED+=("$ex")
    grep -h '^FAIL ' "$HERE/.out/ec2-$ex/checks.log" "$HERE/.out/ec2-$ex/run.log" 2>/dev/null | sed 's/^/        /'
  fi
done

cleanup
trap - EXIT
if [ "${CB_EC2_KEEP:-}" != 1 ]; then
  left="$(leftovers "$RUN")"
  if [ -n "$left" ]; then
    echo "[ec2] LEFT BEHIND by run $RUN:"; echo "$left" | sed 's/^/        /'
    echo "[ec2] remove with: $0 --sweep"
    exit 1
  fi
  log "run $RUN: nothing left behind"
fi
[ "${#FAILED[@]}" -eq 0 ] || { log "failed: ${FAILED[*]}"; exit 1; }
log "all passed: ${EXAMPLES[*]}"
