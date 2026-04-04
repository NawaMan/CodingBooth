// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// boothMessage represents a message sent to a booth user.
type boothMessage struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Body    string `json:"body"`
	Type    string `json:"type"`    // "yes-no" or "text"
	Created string `json:"created"`
	Expires string `json:"expires,omitempty"`
}

// boothMessageResponse represents a user's response to a message.
type boothMessageResponse struct {
	ID       string `json:"id"`
	Answer   string `json:"answer"`
	Answered string `json:"answered"`
}

// resolveMessageTarget resolves the booth container for message commands.
// Uses --name flag, or defaults to the current directory name.
func resolveMessageTarget(name string) (managedContainer, error) {
	containers, err := managedContainers(false)
	if err != nil {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, name, "", nil, stateRunning)
	if err != nil {
		return managedContainer{}, commandExit(1, err.Error())
	}
	return target, nil
}

// MessageSend sends a message to a booth user and waits for a response.
func MessageSend(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("message send", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name (default: current directory)")
	title := flagSet.String("title", "", "Message title")
	body := flagSet.String("body", "", "Message body")
	msgType := flagSet.String("type", "yes-no", "Message type: yes-no or text")
	expires := flagSet.String("expires", "", "Expiry duration (e.g., 5m, 1h)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	if *title == "" {
		return commandExit(1, "Error: --title is required")
	}
	if *body == "" {
		return commandExit(1, "Error: --body is required")
	}
	if *msgType != "yes-no" && *msgType != "text" {
		return commandExit(1, "Error: --type must be 'yes-no' or 'text'")
	}

	target, err := resolveMessageTarget(*name)
	if err != nil {
		return err
	}

	// Generate message ID
	msgID := fmt.Sprintf("msg-%d", time.Now().UnixNano())

	// Build message
	msg := boothMessage{
		ID:      msgID,
		Title:   *title,
		Body:    *body,
		Type:    *msgType,
		Created: time.Now().UTC().Format(time.RFC3339),
	}
	if *expires != "" {
		duration, err := time.ParseDuration(*expires)
		if err != nil {
			return commandExit(1, fmt.Sprintf("Error: invalid --expires duration: %v", err))
		}
		msg.Expires = time.Now().UTC().Add(duration).Format(time.RFC3339)
	}

	// Write message file to .booth/.tmp/messages/
	if target.CodePath == "" {
		return commandExit(1, "Error: booth has no code path; cannot write message file")
	}
	msgDir := filepath.Join(target.CodePath, ".booth", ".tmp", "messages")
	if err := os.MkdirAll(msgDir, 0755); err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to create message directory: %v", err))
	}

	msgData, _ := json.MarshalIndent(msg, "", "  ")
	msgFile := filepath.Join(msgDir, msgID+".msg.json")
	if err := os.WriteFile(msgFile, msgData, 0644); err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to write message file: %v", err))
	}

	// Print the message ID
	fmt.Fprintln(stdout, msgID)

	// Determine display mechanism based on variant
	answer, err := displayMessage(target, msg)
	if err != nil {
		// Clean up message file on display error
		os.Remove(msgFile)
		return err
	}

	// Write response file
	response := boothMessageResponse{
		ID:       msgID,
		Answer:   answer,
		Answered: time.Now().UTC().Format(time.RFC3339),
	}
	respData, _ := json.MarshalIndent(response, "", "  ")
	respFile := filepath.Join(msgDir, msgID+".response.json")
	if err := os.WriteFile(respFile, respData, 0644); err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to write response file: %v", err))
	}

	// Print the answer
	fmt.Fprintln(stdout, answer)

	// Note: message and response files are left in .booth/.tmp/messages/
	// for auditability and to avoid race conditions with external consumers.
	// They are cleaned up automatically when the booth restarts (cleanupBoothTmp).

	return nil
}

// displayMessage dispatches to the right display mechanism based on booth variant.
func displayMessage(target managedContainer, msg boothMessage) (string, error) {
	variant := target.Variant

	switch variant {
	case "desktop-xfce", "desktop-kde", "desktop":
		return displayMessageDesktop(target, msg, variant)
	default:
		// For non-desktop variants (base, codeserver, notebook), fall back to
		// writing the file and waiting for manual response.
		return "", commandExit(1, fmt.Sprintf(
			"Error: variant %q does not support interactive message display yet.\n"+
				"Message written to .booth/.tmp/messages/%s.msg.json\n"+
				"Respond manually: booth exec --name %s -- booth--message respond %s <answer>",
			variant, msg.ID, target.Name, msg.ID))
	}
}

// displayMessageDesktop shows a message via zenity (XFCE) or kdialog (KDE).
// It tries kdialog first for KDE, falling back to zenity if not available.
func displayMessageDesktop(target managedContainer, msg boothMessage, variant string) (string, error) {
	// Detect which dialog tool is available inside the container
	dialogTool := detectDialogTool(target, variant)
	if dialogTool == "" {
		return "", commandExit(1, "Error: neither zenity nor kdialog found in container. Install one first.")
	}

	var cmdArgs []string
	if dialogTool == "kdialog" {
		cmdArgs = buildKDialogArgs(msg)
	} else {
		cmdArgs = buildZenityArgs(msg)
	}

	// Build docker exec args with desktop environment variables
	var execArgs []ilist.List[string]
	execArgs = append(execArgs, ilist.NewList("-u", "coder"))
	execArgs = append(execArgs, ilist.NewList("-e", "DISPLAY=:1"))
	execArgs = append(execArgs, ilist.NewList("-e", "GSK_RENDERER=cairo"))      // GTK4: force software rendering for VNC
	execArgs = append(execArgs, ilist.NewList("-e", "LIBGL_ALWAYS_SOFTWARE=1")) // Mesa: force software GL
	execArgs = append(execArgs, ilist.NewList(target.Name))
	execArgs = append(execArgs, ilist.NewList(cmdArgs...))

	output, err := docker.DockerOutput(
		docker.DockerFlags{Silent: true},
		"exec",
		ilist.NewList(execArgs...),
	)

	output = strings.TrimSpace(output)

	if msg.Type == "yes-no" {
		return interpretYesNoResult(output, err, dialogTool)
	}

	// Text type: output is the user's text
	if err != nil {
		// User cancelled the dialog
		return "cancelled", nil
	}
	return output, nil
}

// detectDialogTool checks which dialog tool (zenity or kdialog) is available in the container.
func detectDialogTool(target managedContainer, variant string) string {
	// Try the preferred tool first based on variant
	preferred := "zenity"
	fallback := "kdialog"
	if variant == "desktop-kde" {
		preferred = "kdialog"
		fallback = "zenity"
	}

	if hasCommand(target.Name, preferred) {
		return preferred
	}
	if hasCommand(target.Name, fallback) {
		return fallback
	}
	return ""
}

// hasCommand checks if a command exists inside a container.
func hasCommand(containerName string, cmd string) bool {
	_, err := docker.DockerOutput(
		docker.DockerFlags{Silent: true},
		"exec",
		ilist.NewList(
			ilist.NewList("-u", "coder"),
			ilist.NewList(containerName),
			ilist.NewList("which", cmd),
		),
	)
	return err == nil
}

// shellQuoteArgs quotes arguments for safe use in a shell command string.
func shellQuoteArgs(args []string) []string {
	quoted := make([]string, len(args))
	for i, arg := range args {
		// If the arg contains special characters, quote it
		if strings.ContainsAny(arg, " \t\n'\"\\$`!#&|;(){}[]<>?*~") {
			quoted[i] = "'" + strings.ReplaceAll(arg, "'", "'\\''") + "'"
		} else {
			quoted[i] = arg
		}
	}
	return quoted
}

// interpretYesNoResult converts zenity/kdialog exit codes to "yes" or "no".
func interpretYesNoResult(output string, err error, variant string) (string, error) {
	if err == nil {
		return "yes", nil
	}

	// Check for exit code
	var dockerErr *docker.DockerExitError
	if isDockerExitError(err, &dockerErr) {
		switch dockerErr.ExitCode {
		case 1:
			// zenity: No/Cancel, kdialog: No
			return "no", nil
		case 2:
			// kdialog: Cancel (for some dialog types)
			return "no", nil
		case 5:
			// zenity: timeout
			return "timeout", nil
		}
	}
	return "", commandExit(1, fmt.Sprintf("Error: dialog command failed: %v", err))
}

// isDockerExitError extracts a DockerExitError from an error chain.
func isDockerExitError(err error, target **docker.DockerExitError) bool {
	if err == nil {
		return false
	}
	if de, ok := err.(*docker.DockerExitError); ok {
		*target = de
		return true
	}
	return false
}

// buildZenityArgs builds zenity command arguments for a message.
func buildZenityArgs(msg boothMessage) []string {
	if msg.Type == "text" {
		return []string{
			"zenity", "--entry",
			"--title=" + msg.Title,
			"--text=" + msg.Body,
			"--width=400",
		}
	}
	// yes-no
	return []string{
		"zenity", "--question",
		"--title=" + msg.Title,
		"--text=" + msg.Body,
		"--ok-label=Yes",
		"--cancel-label=No",
		"--width=400",
	}
}

// buildKDialogArgs builds kdialog command arguments for a message.
func buildKDialogArgs(msg boothMessage) []string {
	if msg.Type == "text" {
		return []string{
			"kdialog",
			"--title", msg.Title,
			"--inputbox", msg.Body,
		}
	}
	// yes-no
	return []string{
		"kdialog",
		"--title", msg.Title,
		"--yesno", msg.Body,
	}
}

// MessageList lists pending messages for a booth.
func MessageList(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("message list", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name (default: current directory)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	target, err := resolveMessageTarget(*name)
	if err != nil {
		return err
	}

	if target.CodePath == "" {
		return commandExit(1, "Error: booth has no code path")
	}

	msgDir := filepath.Join(target.CodePath, ".booth", ".tmp", "messages")
	entries, err := os.ReadDir(msgDir)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprintln(stdout, "No messages.")
			return nil
		}
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".msg.json") {
			continue
		}

		msgID := strings.TrimSuffix(entry.Name(), ".msg.json")
		respFile := filepath.Join(msgDir, msgID+".response.json")

		status := "pending"
		answer := ""
		if _, err := os.Stat(respFile); err == nil {
			status = "answered"
			if data, err := os.ReadFile(respFile); err == nil {
				var resp boothMessageResponse
				if json.Unmarshal(data, &resp) == nil {
					answer = resp.Answer
				}
			}
		}

		// Read message for display
		data, err := os.ReadFile(filepath.Join(msgDir, entry.Name()))
		if err != nil {
			continue
		}
		var msg boothMessage
		if json.Unmarshal(data, &msg) != nil {
			continue
		}

		if status == "answered" {
			fmt.Fprintf(stdout, "%s  [%s]  %s  answer=%s\n", msg.ID, status, msg.Title, answer)
		} else {
			fmt.Fprintf(stdout, "%s  [%s]  %s\n", msg.ID, status, msg.Title)
		}
	}
	return nil
}

// MessageResponse reads the response for a specific message.
func MessageResponse(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("message response", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name (default: current directory)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	positional := flagSet.Args()
	if len(positional) < 1 {
		return commandExit(1, "Error: usage: booth message response [--name <booth>] <msg-id>")
	}
	msgID := positional[0]

	target, err := resolveMessageTarget(*name)
	if err != nil {
		return err
	}

	if target.CodePath == "" {
		return commandExit(1, "Error: booth has no code path")
	}

	respFile := filepath.Join(target.CodePath, ".booth", ".tmp", "messages", msgID+".response.json")
	data, err := os.ReadFile(respFile)
	if err != nil {
		if os.IsNotExist(err) {
			return commandExit(1, "Error: no response yet for message "+msgID)
		}
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}

	fmt.Fprintln(stdout, string(data))
	return nil
}

// Message dispatches message subcommands.
func Message(args []string, stdout io.Writer, stderr io.Writer) error {
	if len(args) == 0 {
		return commandExit(1, "Error: usage: booth message <send|list|response> [options]")
	}

	subcommand := args[0]
	subArgs := args[1:]

	switch subcommand {
	case "send":
		return MessageSend(subArgs, stdout, stderr)
	case "list":
		return MessageList(subArgs, stdout, stderr)
	case "response":
		return MessageResponse(subArgs, stdout, stderr)
	default:
		return commandExit(1, fmt.Sprintf("Error: unknown message subcommand %q. Use: send, list, response", subcommand))
	}
}
