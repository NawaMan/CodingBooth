// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import "fmt"

func showVersion(version string) {
	banner := `   _____          _ _             ____              _   _
  / ____|        | (_)           |  _ \            | | | |
 | |     ___   __| |_ _ __   __ _| |_) | ___   ___ | |_| |__
 | |    / _ \ / _` + "`" + ` | | '_ \ / _` + "`" + ` |  _ < / _ \ / _ \| __| '_ \
 | |___| (_) | (_| | | | | | (_| | |_) | (_) | (_) | |_| | | |
  \_____\___/ \__,_|_|_| |_|\__, |____/ \___/ \___/ \__|_| |_|
                             __/ |
                            |___/                             `
	fmt.Println(banner)
	fmt.Printf("CodingBooth: %s\n", version)
}
