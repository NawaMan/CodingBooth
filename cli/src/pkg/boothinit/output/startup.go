// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

// SerializeStartup produces the content of a .booth/startup.sh file.
// Returns empty string if there is no content.
func SerializeStartup(sc *StartupContent, command, adjustCommand string) string {
	if sc == nil || sc.Content == "" {
		return ""
	}
	header := formatGeneratedHeader("#", command, adjustCommand)
	return "#!/bin/bash\nset -e\n" + header + "\n" + sc.Content
}
