package main

import "fmt"

// version is set at build time via -ldflags "-X main.version=$(cat version.txt)"
var version = "dev" // fallback if not set at build time

func showVersion() {
	banner := `__      __       _    ___                   
\ \    / /__ _ _| |__/ __|_ __  __ _ __ ___ 
 \ \/\/ / _ \ '_| / /\__ \ '_ \/ _` + "`" + ` / _/ -_)
  \_/\_/\___/_| |_\_\|___/ .__/\__,_\__\___|
                         |_|                `
	fmt.Println(banner)
	fmt.Printf("WorkSpace: %s\n", version)
}
