// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// What booth dash's detail pane reads about one booth, beyond `booth list`.

// BoothStats is one sample of a running booth's resource use, as the engine
// prints it ("1.25%", "312MiB / 15.5GiB", "2.0%").
type BoothStats struct {
	CPU     string
	Memory  string
	MemPerc string
}

// Stats samples a running booth's CPU and memory once.
func Stats(b Booth) (BoothStats, error) {
	if b.Engine == docker.EngineApple {
		return BoothStats{}, fmt.Errorf("not available on engine apple")
	}
	out, err := exec.Command(docker.EngineBinary(b.Engine), "stats", "--no-stream",
		"--format", "{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}", b.Name).Output()
	if err != nil {
		return BoothStats{}, engineError(err)
	}
	return parseStats(string(out))
}

func parseStats(out string) (BoothStats, error) {
	fields := strings.Split(strings.TrimSpace(out), "\t")
	if len(fields) != 3 || fields[0] == "" {
		return BoothStats{}, fmt.Errorf("unexpected stats output %q", strings.TrimSpace(out))
	}
	return BoothStats{CPU: strings.TrimSpace(fields[0]), Memory: strings.TrimSpace(fields[1]),
		MemPerc: strings.TrimSpace(fields[2])}, nil
}

// BoothPresence is how many browser pages show the booth (the presence
// heartbeat): Viewers counts them all, Background those not in view.
type BoothPresence struct {
	Viewers    int `json:"viewers"`
	Background int `json:"background"`
	Expected   int `json:"expected"`
}

// BoothIdle is the booth's idle shutdown setting. Times are seconds;
// PauseUntil is a Unix time, 0 when not paused.
type BoothIdle struct {
	Enabled      bool  `json:"enabled"`
	IdleTime     int   `json:"idle_time"`
	ShutdownTime int   `json:"shutdown_time"`
	Disabled     bool  `json:"disabled"`
	PauseUntil   int64 `json:"pause_until"`
}

// BoothState is what the booth's own message API says about it.
type BoothState struct {
	Presence BoothPresence
	Idle     BoothIdle
}

// The message API inside the booth: the console listens on 10000 and its API
// on 10007. Asked from inside the container, so a password-gated or --public
// booth answers the same as a plain one.
const boothAPI = "http://127.0.0.1:10007/booth-messages/api/"

// State asks a running booth's message API for its viewers and idle setting,
// in one exec.
func State(b Booth) (BoothState, error) {
	script := "curl -fsS --max-time 2 " + boothAPI + "presence && echo && curl -fsS --max-time 2 " + boothAPI + "idle/state"
	out, err := exec.Command(docker.EngineBinary(b.Engine), "exec", b.Name, "sh", "-c", script).Output()
	if err != nil {
		return BoothState{}, fmt.Errorf("its message API did not answer")
	}
	return parseState(string(out))
}

func parseState(out string) (BoothState, error) {
	lines := strings.SplitN(strings.TrimSpace(out), "\n", 2)
	var state BoothState
	if len(lines) != 2 {
		return state, fmt.Errorf("unexpected API answer")
	}
	if err := json.Unmarshal([]byte(lines[0]), &state.Presence); err != nil {
		return state, fmt.Errorf("unexpected presence answer: %v", err)
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(lines[1])), &state.Idle); err != nil {
		return state, fmt.Errorf("unexpected idle answer: %v", err)
	}
	return state, nil
}

// PendingMessage is a `booth message send` the booth user has not answered.
type PendingMessage struct {
	ID    string
	Title string
	Type  string
}

// PendingMessages lists the booth's unanswered, unexpired messages, oldest
// first. Toasts and banners need no answer and are left out.
func PendingMessages(b Booth) ([]PendingMessage, error) {
	dir := b.BoothDir
	if dir == "" {
		if b.CodePath == "" {
			return nil, nil
		}
		dir = filepath.Join(b.CodePath, ".booth")
	}
	return pendingMessagesIn(filepath.Join(dir, ".tmp", "messages"), time.Now())
}

func pendingMessagesIn(dir string, now time.Time) ([]PendingMessage, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.msg.json"))
	if err != nil {
		return nil, err
	}
	type dated struct {
		PendingMessage
		created string
	}
	var pending []dated
	for _, file := range files {
		id := strings.TrimSuffix(filepath.Base(file), ".msg.json")
		if _, err := os.Stat(filepath.Join(dir, id+".response.json")); err == nil {
			continue
		}
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}
		var msg boothMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type == "toast" || msg.Type == "banner" {
			continue
		}
		if msg.Expires != "" {
			if at, err := time.Parse(time.RFC3339, msg.Expires); err == nil && !at.After(now) {
				continue
			}
		}
		pending = append(pending, dated{PendingMessage{ID: id, Title: msg.Title, Type: msg.Type}, msg.Created})
	}
	sort.SliceStable(pending, func(i, j int) bool { return pending[i].created < pending[j].created })
	out := make([]PendingMessage, len(pending))
	for i, p := range pending {
		out[i] = p.PendingMessage
	}
	return out, nil
}

// engineError is the engine's own complaint when it wrote one.
func engineError(err error) error {
	if exitErr, ok := err.(*exec.ExitError); ok {
		if msg := strings.TrimSpace(string(exitErr.Stderr)); msg != "" {
			lines := strings.Split(msg, "\n")
			return fmt.Errorf("%s", lines[len(lines)-1])
		}
	}
	return err
}
