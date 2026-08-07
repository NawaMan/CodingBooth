#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant xfce --port 50411 --select java:17/android-sdk+emulator+kvm

if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM: /dev/kvm is already accessible — emulator will be hardware-accelerated."
  elif sudo -n chmod 0666 /dev/kvm 2>/dev/null; then
    # The node inherits the host's root:kvm 0660, which coder is not a member of.
    # /dev is a container-private tmpfs, so this does not affect the host.
    echo "KVM: relaxed /dev/kvm permissions for the booth user (container-local)."
  else
    echo "KVM: /dev/kvm present but not writable, and sudo is unavailable."
    echo "     The emulator will need '-accel off' (software emulation, much slower)."
  fi
else
  echo "KVM: /dev/kvm not present — was the booth started without the kvm run-args?"
  echo "     The emulator will need '-accel off' (software emulation, much slower)."
fi
