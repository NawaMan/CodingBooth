// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

// SerializeBoothfile produces the content of a .booth/Boothfile.
// Returns empty string if there is no content.
func SerializeBoothfile(bf *BoothfileContent, command, adjustCommand string) string {
	if bf == nil || bf.Content == "" {
		return ""
	}
	header := formatGeneratedHeader("#", command, adjustCommand)
	return "# syntax=codingbooth/boothfile:1\n" + header + "\n" + bf.Content
}
