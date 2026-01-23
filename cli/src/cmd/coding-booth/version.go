// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import "fmt"

func showVersion(version string) {
	banner := `_________            .___.__              __________               __  .__     
\_   ___ \  ____   __| _/|__| ____    ____\______   \ ____   _____/  |_|  |__  
/    \  \/ /  _ \ / __ | |  |/    \  / ___\|    |  _//  _ \ /  _ \   __\  |  \ 
\     \___(  <_> ) /_/ | |  |   |  \/ /_/  >    |   (  <_> |  <_> )  | |   Y  \
 \______  /\____/\____ | |__|___|  /\___  /|______  /\____/ \____/|__| |___|  /
        \/            \/         \//_____/        \/                        \/ `
	fmt.Println(banner)
	fmt.Printf("CodingBooth: %s\n", version)
}
