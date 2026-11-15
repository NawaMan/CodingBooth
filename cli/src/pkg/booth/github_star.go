// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"strings"
)

// The GitHub star prompt: after a while in a booth's web UI the overlay shows a toast
// with a link to star the project on GitHub. Once the link is clicked it is never shown
// again — in any booth on this host.
//
// The click lands in the container: the overlay posts it, and the booth's API server
// writes GitHubStarTmpName into .booth/.tmp/. That folder is emptied when the booth
// exits and again when one starts, so before either, PromoteGitHubStar copies the click
// into a marker in the user's config folder. Every booth started afterwards is told
// "done" through BOOTH_STAR_PROMPT and the overlay stays quiet.
//
// CB_STAR_PROMPT=off on the host turns the prompt off for booths started with it
// (demos, recordings, hosted booths).

// GitHubStarTmpName is the file in .booth/.tmp/ the booth writes when the star link is clicked.
const GitHubStarTmpName = "github-star"

// githubStarMarker is the user-wide marker: the link was clicked in some booth. "" when
// the config folder is unknown.
func githubStarMarker() string {
	base, err := os.UserConfigDir()
	if err != nil || base == "" {
		return ""
	}
	return filepath.Join(base, "codingbooth", "github-star")
}

// PromoteGitHubStar records a click found in boothDir/.tmp/ in the user-wide marker.
// A failure only means the prompt may come back once more.
func PromoteGitHubStar(boothDir string) {
	promoteGitHubStarTo(boothDir, githubStarMarker())
}

func promoteGitHubStarTo(boothDir, marker string) {
	if boothDir == "" || marker == "" {
		return
	}
	if _, err := os.Stat(filepath.Join(boothDir, ".tmp", GitHubStarTmpName)); err != nil {
		return
	}
	if _, err := os.Stat(marker); err == nil {
		return
	}
	if err := os.MkdirAll(filepath.Dir(marker), 0755); err != nil {
		return
	}
	_ = os.WriteFile(marker, []byte("The GitHub star link was clicked in a booth; the prompt is not shown again.\n"), 0644)
}

// githubStarPrompt is the BOOTH_STAR_PROMPT value for a new booth: "off" when the
// host turned it off (CB_STAR_PROMPT = off/false/no/0), "done" when the link was
// already clicked, otherwise "on".
func githubStarPrompt(setting, marker string) string {
	switch strings.ToLower(strings.TrimSpace(setting)) {
	case "off", "false", "no", "0":
		return "off"
	}
	if marker != "" {
		if _, err := os.Stat(marker); err == nil {
			return "done"
		}
	}
	return "on"
}

// GitHubStarPrompt is githubStarPrompt for this host.
func GitHubStarPrompt() string {
	return githubStarPrompt(os.Getenv("CB_STAR_PROMPT"), githubStarMarker())
}
