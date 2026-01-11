// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import "fmt"

func showVersion(version string) {
	banner := `__      __       _    ___                   
\ \    / /__ _ _| |__/ __|_ __  __ _ __ ___ 
 \ \/\/ / _ \ '_| / /\__ \ '_ \/ _` + "`" + ` / _/ -_)
  \_/\_/\___/_| |_\_\|___/ .__/\__,_\__\___|
                         |_|                `
	fmt.Println(banner)
	fmt.Printf("WorkSpace: %s\n", version)
}
