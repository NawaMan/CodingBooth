// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"io"
)

// Keep this public schema independent of internal inspection fields, especially
// environment variables and security details added for other lifecycle commands.
type boothListEntry struct {
	Name      string `json:"name"`
	Engine    string `json:"engine"`
	State     string `json:"state"`
	Variant   string `json:"variant"`
	CodePath  string `json:"code_path"`
	Port      string `json:"port"`
	Daemon    bool   `json:"daemon"`
	KeepAlive bool   `json:"keep_alive"`
	CreatedAt string `json:"created_at"`
}

func writeBoothListJSON(containers []managedContainer, stdout io.Writer) error {
	entries := make([]boothListEntry, 0, len(containers))
	for _, container := range containers {
		entries = append(entries, boothListEntry{
			Name: container.Name, Engine: container.Engine, State: container.State,
			Variant: container.Variant, CodePath: container.CodePath, Port: container.Port,
			Daemon: container.Daemon, KeepAlive: container.KeepAlive, CreatedAt: container.CreatedAt,
		})
	}
	return json.NewEncoder(stdout).Encode(entries)
}
