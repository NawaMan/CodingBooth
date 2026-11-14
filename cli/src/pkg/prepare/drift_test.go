// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package prepare

// Drift guard for the copies that `booth prepare` runs instead of the real
// files (docs/REUSE_BOOTH.md). Each copy is written by hand from a file under
// variants/base/, and nothing else notices when the original moves on:
//
//   - experiments/host-provision/booth-entry and booth--as-coder must be the
//     real scripts plus CB_TARGET guard lines and the marked user exception;
//   - base-provision.sh must run the base Dockerfile's setups, in order;
//   - base-provision.sh names the sha256 of the Dockerfile it was last checked
//     against, so any other base change also stops here until someone looks.

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

const repoRoot = "../../../.."

func readRepoFile(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(repoRoot, rel))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	// A Windows checkout may have CRLF line ends; the copies are compared by content.
	return strings.ReplaceAll(string(b), "\r\n", "\n")
}

// assertGuardedCopy checks that copyRel is realRel with only two kinds of change:
// lines carrying a "# CB_TARGET:" / "# CB_TARGET exception" marker (the if/fi
// guards and the exception's comment), and the exception lines in `exceptions`
// (copy line -> the real line it replaces).
func assertGuardedCopy(t *testing.T, realRel, copyRel string, exceptions map[string]string) {
	t.Helper()
	real := strings.Split(readRepoFile(t, realRel), "\n")
	cp := strings.Split(readRepoFile(t, copyRel), "\n")

	seen := map[string]bool{}
	var stripped []string
	for _, line := range cp {
		if orig, ok := exceptions[line]; ok {
			seen[line] = true
			stripped = append(stripped, orig)
			continue
		}
		if strings.Contains(line, "# CB_TARGET:") || strings.Contains(line, "# CB_TARGET exception") {
			continue
		}
		stripped = append(stripped, line)
	}
	for line := range exceptions {
		if !seen[line] {
			t.Errorf("%s: exception line not found (update the test if it changed on purpose):\n  %s", copyRel, line)
		}
	}

	if len(stripped) == len(real) {
		same := true
		for i := range real {
			if real[i] != stripped[i] {
				same = false
				break
			}
		}
		if same {
			return
		}
	}
	// Report the first difference, with line numbers in the real file.
	i := 0
	for i < len(real) && i < len(stripped) && real[i] == stripped[i] {
		i++
	}
	at := func(lines []string, i int) string {
		if i < len(lines) {
			return lines[i]
		}
		return "<end of file>"
	}
	t.Errorf("%s has drifted from %s: without its CB_TARGET lines, the first difference is at %s line %d\n"+
		"  real: %s\n  copy: %s\n"+
		"Bring the change across (wrapping it in a CB_TARGET guard only if it is container-only).",
		copyRel, realRel, realRel, i+1, at(real, i), at(stripped, i))
}

func TestDrift_BoothEntryCopy(t *testing.T) {
	assertGuardedCopy(t, "variants/base/booth-entry", "experiments/host-provision/booth-entry", map[string]string{
		`USER_NAME="${CB_USER_NAME:-coder}"`:                         `USER_NAME="coder"`,
		`HOME_DIR="${CB_USER_HOME:-/home/${USER_NAME}}"`:             `HOME_DIR="/home/${USER_NAME}"`,
		`CODE_DIR="${CB_CODE_DIR:-/home/${USER_NAME}/${CODE_NAME}}"`: `CODE_DIR="/home/${USER_NAME}/${CODE_NAME}"`,
	})
}

func TestDrift_BoothAsCoderCopy(t *testing.T) {
	assertGuardedCopy(t, "variants/base/booth--as-coder", "experiments/host-provision/booth--as-coder", map[string]string{
		`USER_NAME="${CB_USER_NAME:-coder}"   # CB_TARGET exception: unchanged when unset`: `USER_NAME="coder"`,
	})
}

// skippedBaseSetups are the base Dockerfile's setups that base-provision.sh
// deliberately does not run. Each must also have a `skip "<name>…"` line there,
// so the provisioning log says so.
var skippedBaseSetups = map[string]string{
	"cleanup-after--setup.sh":         "wipes /tmp, /var/tmp and /root/.cache: an image-size step",
	"booth-message-wrapper--setup.sh": "the nginx message overlay: container-only",
}

var setupCmd = regexp.MustCompile(`^([A-Za-z0-9._-]+--setup\.sh)\b`)

// dockerfileSetupRuns returns each `RUN <x>--setup.sh …` instruction, with its
// continuation lines joined and whitespace collapsed.
func dockerfileSetupRuns(dockerfile string) []string {
	var runs []string
	var cur strings.Builder
	cont := false
	for _, line := range strings.Split(dockerfile, "\n") {
		trimmed := strings.TrimSpace(line)
		if !cont {
			if !strings.HasPrefix(trimmed, "RUN ") {
				continue
			}
			trimmed = strings.TrimSpace(strings.TrimPrefix(trimmed, "RUN "))
			cur.Reset()
		}
		cont = strings.HasSuffix(trimmed, `\`)
		cur.WriteString(strings.TrimSuffix(trimmed, `\`))
		cur.WriteString(" ")
		if !cont {
			cmd := strings.Join(strings.Fields(cur.String()), " ")
			if setupCmd.MatchString(cmd) {
				runs = append(runs, cmd)
			}
		}
	}
	return runs
}

var runSetupLine = regexp.MustCompile(`^run_setup\s+(.+)$`)

func TestDrift_BaseProvisionRunsTheBaseSetups(t *testing.T) {
	dockerfile := readRepoFile(t, "variants/base/Dockerfile")
	script := readRepoFile(t, "experiments/host-provision/base-provision.sh")

	var want []string
	for _, cmd := range dockerfileSetupRuns(dockerfile) {
		name := setupCmd.FindStringSubmatch(cmd)[1]
		if _, skipped := skippedBaseSetups[name]; skipped {
			if !strings.Contains(script, `skip "`+name) {
				t.Errorf("base-provision.sh skips %s but has no `skip \"%s: <why>\"` line", name, name)
			}
			continue
		}
		want = append(want, cmd)
	}
	if len(want) == 0 {
		t.Fatal("found no `RUN <x>--setup.sh` lines in the base Dockerfile; the parser is out of date")
	}

	var got []string
	for _, line := range strings.Split(script, "\n") {
		if m := runSetupLine.FindStringSubmatch(strings.TrimSpace(line)); m != nil {
			got = append(got, strings.Join(strings.Fields(strings.Trim(m[1], `"`)), " "))
		}
	}

	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("base-provision.sh's run_setup lines do not match the base Dockerfile's setups.\n"+
			"Dockerfile (in order):\n  %s\nbase-provision.sh:\n  %s\n"+
			"Mirror the change, or add the setup to skippedBaseSetups with a reason.",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
}

var mirrorsHash = regexp.MustCompile(`(?m)^# mirrors variants/base/Dockerfile sha256: ([0-9a-f]{64})$`)

func TestDrift_BaseProvisionReviewedAgainstThisDockerfile(t *testing.T) {
	script := readRepoFile(t, "experiments/host-provision/base-provision.sh")
	m := mirrorsHash.FindStringSubmatch(script)
	if m == nil {
		t.Fatal("base-provision.sh has no `# mirrors variants/base/Dockerfile sha256: <hex>` line")
	}
	sum := sha256.Sum256([]byte(readRepoFile(t, "variants/base/Dockerfile")))
	if got := hex.EncodeToString(sum[:]); got != m[1] {
		t.Errorf("variants/base/Dockerfile changed since base-provision.sh was last checked against it\n"+
			"  recorded: %s\n  now:      %s\n"+
			"Mirror the base change in experiments/host-provision/base-provision.sh (or add a skip line\n"+
			"saying why it does not apply off-booth), then record the new hash there.",
			m[1], got)
	}
}
