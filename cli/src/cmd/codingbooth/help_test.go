package main

import (
	"io"
	"os"
	"regexp"
	"strings"
	"testing"
)

// captureStdout runs fn and returns what it printed to stdout.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved := os.Stdout
	os.Stdout = w
	defer func() { os.Stdout = saved }()

	done := make(chan string)
	go func() {
		b, _ := io.ReadAll(r)
		done <- string(b)
	}()
	fn()
	w.Close()
	return <-done
}

// optionFlags returns the flags that start an option line ("  --name ...").
func optionFlags(text string) []string {
	re := regexp.MustCompile(`(?m)^  (--[a-z][a-z-]*)`)
	var flags []string
	for _, m := range re.FindAllStringSubmatch(text, -1) {
		flags = append(flags, m[1])
	}
	return flags
}

func detailHas(detail, flag string) bool {
	return regexp.MustCompile(`(?m)^  ` + regexp.QuoteMeta(flag) + `\b`).MatchString(detail)
}

// The short page is a selection: every flag on it is also documented in the
// full reference, so --help --detail never knows less than --help.
func TestShortHelpFlagsAreInDetail(t *testing.T) {
	short := captureStdout(t, func() { showHelp("test") })
	detail := captureStdout(t, func() { showHelpDetail("test") })

	flags := optionFlags(short)
	if len(flags) < 10 {
		t.Fatalf("found only %d option lines on the short page: %v", len(flags), flags)
	}
	for _, f := range flags {
		if !detailHas(detail, f) {
			t.Errorf("%s is on the short page but not in --help --detail", f)
		}
	}
}

// Flags kept off the short page on purpose, because they are safety
// overrides or rarely needed. They must stay in the full reference.
func TestFlagsLeftOffShortHelpStayInDetail(t *testing.T) {
	short := captureStdout(t, func() { showHelp("test") })
	detail := captureStdout(t, func() { showHelpDetail("test") })

	for _, f := range []string{
		"--ok-public", "--dind-allowed", "--hide-welcome",
		"--privileged-allowed", "--no-sudo", "--rootless",
	} {
		if detailHas(short, f) {
			t.Errorf("%s should not be an option line on the short page", f)
		}
		if !detailHas(detail, f) {
			t.Errorf("%s is missing from --help --detail", f)
		}
	}
}

func TestShortHelpListsProfileAndRunFlags(t *testing.T) {
	short := captureStdout(t, func() { showHelp("test") })
	for _, f := range []string{"--profile", "--keep-alive", "--persist-home", "--writable-booth"} {
		if !detailHas(short, f) {
			t.Errorf("%s should be on the short page", f)
		}
	}
	for _, row := range []string{"CONFIG ", "EXAMPLE ", "SHOWCASE "} {
		if !strings.Contains(short, "\n  "+row) {
			t.Errorf("OTHER COMMANDS should have its own %q row", strings.TrimSpace(row))
		}
	}
}
