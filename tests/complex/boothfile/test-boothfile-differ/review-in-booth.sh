#!/bin/bash
# Runs inside the booth: the first five minutes of differ on a scratch repo.
# Prints SCREEN and REVIEW sections for the host-side test to assert on.
#
# differ asks the terminal for its background colour and cursor position at
# start and waits for the answers. tmux gives them (a bare pty from `script`
# does not), and tmux is also what differ is built to run beside.
set -uo pipefail

repo="$(mktemp -d)"
cd "$repo"
git init -q
printf 'package main\n\nfunc main() {}\n' > main.go
git add main.go
git -c user.email=booth@test -c user.name=booth commit -qm init
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("hello-differ") }\n' > main.go

tmux new-session -d -s differ-test -x 140 -y 35 -c "$repo" "differ review"
sleep 3
echo "=== SCREEN"
tmux capture-pane -p -t differ-test

# Comment on the line under the cursor, the way a user would: c, type, ctrl+s.
tmux send-keys -t differ-test c
sleep 1
tmux send-keys -t differ-test -l "comment-from-booth-test"
tmux send-keys -t differ-test C-s
sleep 2
echo "=== REVIEW"
cat "$repo/.git/differ/review.json" 2>/dev/null || echo "<no review.json>"

tmux kill-session -t differ-test 2>/dev/null || true
rm -rf "$repo"
