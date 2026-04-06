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

)

// boothMessage represents a message sent to a booth user.
type boothMessage struct {
	ID      string   `json:"id"`
	Title   string   `json:"title"`
	Body    string   `json:"body"`
	Type    string   `json:"type"`              // "yes-no", "text", "ok", "choice", "password", "toast"
	Options []string `json:"options,omitempty"`  // for "choice" type
	Created string   `json:"created"`
	Expires string   `json:"expires,omitempty"`
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
	msgType := flagSet.String("type", "yes-no", "Message type: yes-no, text, ok, choice, password, toast")
	options := flagSet.String("options", "", "Comma-separated options for 'choice' type")
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
	validTypes := map[string]bool{"yes-no": true, "yes-no-cancel": true, "text": true, "ok": true, "choice": true, "password": true, "toast": true}
	if !validTypes[*msgType] {
		return commandExit(1, "Error: --type must be one of: yes-no, yes-no-cancel, text, ok, choice, password, toast")
	}
	if *msgType == "choice" && *options == "" {
		return commandExit(1, "Error: --options is required for 'choice' type")
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
	if *options != "" {
		msg.Options = strings.Split(*options, ",")
	}
	if *expires != "" {
		duration, err := time.ParseDuration(*expires)
		if err != nil {
			return commandExit(1, fmt.Sprintf("Error: invalid --expires duration: %v", err))
		}
		msg.Expires = time.Now().UTC().Add(duration).Format(time.RFC3339)
	} else if *msgType == "toast" {
		// Default toast duration: 30 seconds
		msg.Expires = time.Now().UTC().Add(30 * time.Second).Format(time.RFC3339)
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

	// Toast is fire-and-forget — no response expected
	if *msgType == "toast" {
		return nil
	}

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

// displayMessage waits for the in-container web overlay to handle the message.
// All variants use the nginx + iframe + overlay pattern, so the web UI
// polls for .msg.json files and writes .response.json.
func displayMessage(target managedContainer, msg boothMessage) (string, error) {
	return waitForResponse(target, msg)
}

// waitForResponse waits for a .response.json file to appear (written by the in-container extension).
func waitForResponse(target managedContainer, msg boothMessage) (string, error) {
	msgDir := filepath.Join(target.CodePath, ".booth", ".tmp", "messages")
	respFile := filepath.Join(msgDir, msg.ID+".response.json")

	// Determine timeout
	timeout := 10 * time.Minute // default
	if msg.Expires != "" {
		expiresAt, err := time.Parse(time.RFC3339, msg.Expires)
		if err == nil {
			timeout = time.Until(expiresAt)
			if timeout <= 0 {
				return "timeout", nil
			}
		}
	}

	deadline := time.After(timeout)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	fmt.Fprintf(os.Stderr, "Waiting for response (variant: %s)...\n", target.Variant)

	for {
		select {
		case <-deadline:
			return "timeout", nil
		case <-ticker.C:
			data, err := os.ReadFile(respFile)
			if err != nil {
				continue // Not yet
			}
			var resp boothMessageResponse
			if err := json.Unmarshal(data, &resp); err != nil {
				continue
			}
			return resp.Answer, nil
		}
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
