// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"fmt"
	"os/exec"
	"runtime"
)

func openURL(url string) error {
	var command *exec.Cmd
	switch runtime.GOOS {
	case "linux":
		command = exec.Command("xdg-open", url)
	case "darwin":
		command = exec.Command("open", url)
	case "windows":
		command = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		return fmt.Errorf("no browser opener for %s", runtime.GOOS)
	}
	return command.Start()
}
