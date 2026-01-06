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
