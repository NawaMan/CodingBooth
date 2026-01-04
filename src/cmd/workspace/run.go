package main

import (
	"fmt"
	"os"

	"github.com/BurntSushi/toml"
	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/workspace/src/pkg/appctx"
)

func runWorkspace() {
	ctx := initializeAppContext(os.Args)
	fmt.Printf("%+v\n", ctx)

	// Execute workspace pipeline
	// ctx = workspace.PortDetermination(ctx)

	// TODO: Continue with remaining pipeline steps
	// - ShowDebugBanner
	// - SetupDind
	// - PrepareCommonArgs
	// - PrepareKeepAliveArgs
	// - PrepareTtyArgs
	// - RunAsDaemon / RunAsForeground / RunAsCommand

	os.Exit(0)
}

// initializeAppContext creates an AppContext with default values matching workspace.sh Main()
func initializeAppContext(args []string) appctx.AppContext {
	config := appctx.AppConfig{}
	if err := readFromEnvVars(&config); err != nil {
		panic(fmt.Errorf("failed to read env vars: %w", err))
	}
	configFile := config.ConfigFile
	if err := readFromToml(configFile, &config); err != nil {
		panic(fmt.Errorf("failed to read env vars: %w", err))
	}

	context := appctx.AppContextBuilder{
		Config: config,
	}

	// 	ctx.ScriptName = getScriptName()
	// 	ctx.ScriptDir = getScriptDir()
	// 	ctx.LibDir = filepath.Join(ctx.ScriptDir, "libs")
	// 	ctx.WorkspacePath = getCurrentPath()
	// 	ctx.ProjectName = getProjectName(ctx.WorkspacePath)
	// 	ctx.HostUID = getHostUID()
	// 	ctx.HostGID = getHostGID()
	// 	ctx.Timezone = detectTimezone()

	// 	ctx.ConfigFile = "./ws-config.toml"
	// 	ctx.PrebuildRepo = "nawaman/workspace"

	// 	runner.ReadContextFromEnvVars(ctx)

	// 	configFileSet := readVerboseDryrunAndConfigFile(args, ctx)
	// 	if configFileSet {
	// 		if err := applyContextFromConfigFile(ctx.ConfigFile, ctx); err != nil {
	// 			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	// 			os.Exit(1)
	// 		}
	// 	}

	// 	// // Parse command-line arguments (overrides config)
	// 	// if err := parseArgs(os.Args[1:], builder); err != nil {
	// 	// 	fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	// 	// 	os.Exit(1)
	// 	// }

	return context.Build()
}

func readFromEnvVars(config *appctx.AppConfig) error {
	return envconfig.Process("WS", config)
}

func readFromToml(path string, config *appctx.AppConfig) error {
	if _, err := toml.DecodeFile(path, config); err != nil {
		return err
	}
	return nil
}

// // getCurrentPath returns the current working directory, handling MSYS/Git Bash on Windows
// func getCurrentPath() string {
// 	cwd, err := os.Getwd()
// 	if err != nil {
// 		fmt.Fprintf(os.Stderr, "Error getting current directory: %v\n", err)
// 		os.Exit(1)
// 	}

// 	if runtime.GOOS == "windows" {
// 		return cwd
// 	}

// 	return cwd
// }

// // getScriptName returns the base name of the executable
// func getScriptName() string {
// 	if len(os.Args) > 0 {
// 		return filepath.Base(os.Args[0])
// 	}
// 	return "workspace"
// }

// // getScriptDir returns the directory containing the executable
// func getScriptDir() string {
// 	if len(os.Args) == 0 {
// 		return "."
// 	}

// 	exePath := os.Args[0]

// 	// Get absolute path
// 	absPath, err := filepath.Abs(exePath)
// 	if err != nil {
// 		return filepath.Dir(exePath)
// 	}

// 	// Resolve symlinks
// 	realPath, err := filepath.EvalSymlinks(absPath)
// 	if err != nil {
// 		return filepath.Dir(absPath)
// 	}

// 	return filepath.Dir(realPath)
// }

// // getProjectName extracts a sanitized project name from the workspace path
// func getProjectName(workspacePath string) string {
// 	// Get the base name of the path
// 	baseName := filepath.Base(workspacePath)

// 	// Sanitize: replace non-alphanumeric characters with underscores
// 	// This matches the workspace.sh project_name function behavior
// 	var result strings.Builder
// 	for _, ch := range baseName {
// 		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
// 			result.WriteRune(ch)
// 		} else {
// 			result.WriteRune('_')
// 		}
// 	}

// 	sanitized := result.String()
// 	if sanitized == "" {
// 		return "workspace"
// 	}

// 	return sanitized
// }

// // getHostUID returns the current user's UID as a string
// func getHostUID() string {
// 	if runtime.GOOS == "windows" {
// 		// Windows doesn't have UIDs, return a default
// 		return "1000"
// 	}

// 	// Use id -u command
// 	cmd := exec.Command("id", "-u")
// 	output, err := cmd.Output()
// 	if err != nil {
// 		return "1000" // fallback
// 	}

// 	return strings.TrimSpace(string(output))
// }

// // getHostGID returns the current user's GID as a string
// func getHostGID() string {
// 	if runtime.GOOS == "windows" {
// 		// Windows doesn't have GIDs, return a default
// 		return "1000"
// 	}

// 	// Use id -g command
// 	cmd := exec.Command("id", "-g")
// 	output, err := cmd.Output()
// 	if err != nil {
// 		return "1000" // fallback
// 	}

// 	return strings.TrimSpace(string(output))
// }

// // detectTimezone detects the system timezone
// func detectTimezone() string {
// 	// Try to get timezone from environment
// 	if tz := os.Getenv("TZ"); tz != "" {
// 		return tz
// 	}

// 	// Use Go's time package to detect local timezone
// 	now := time.Now()
// 	zone, _ := now.Zone()

// 	// If we can get the IANA timezone name, use it
// 	if loc := now.Location(); loc != nil && loc.String() != "Local" {
// 		return loc.String()
// 	}

// 	// Fallback to zone abbreviation (e.g., "EST", "PST")
// 	if zone != "" {
// 		return zone
// 	}

// 	// Ultimate fallback
// 	return "UTC"
// }

// // readVerboseDryrunAndConfigFile parses arguments looking for config file and verbosity settings.
// // Return if the config file was set.
// // This allows loading configuration before full argument parsing.
// func readVerboseDryrunAndConfigFile(args []string, builder *appctx.AppContextBuilder) bool {
// 	configFileSet := false
// 	for i := 0; i < len(args); i++ {
// 		arg := args[i]
// 		switch arg {
// 		case "--config":
// 			if i+1 < len(args) {
// 				builder.ConfigFile = args[i+1]
// 				configFileSet = true
// 				i++
// 			}
// 		case "--verbose":
// 			builder.Verbose = true
// 		case "--dryrun":
// 			builder.Dryrun = true
// 		case "--silence-build":
// 			builder.SilenceBuild = true
// 		}
// 	}
// 	return configFileSet
// }

// // Read and apply context from config file
// func applyContextFromConfigFile(configFile string, ctx *appctx.AppContextBuilder) error {
// 	data, err := os.ReadFile(configFile)
// 	if err != nil {
// 		return err
// 	}

// 	toml.Unmarshal(data, ctx)
// 	return nil
// }

// // readArgs parses command-line arguments and applies them to the builder.
// // This matches the behavior of workspace.sh ParseArgs function.
// func readArgs(args []string, builder *appctx.AppContextBuilder) error {
// 	parsingCmds := false
// 	i := 0

// 	for i < len(args) {
// 		arg := args[i]

// 		// After --, everything is a command
// 		if parsingCmds {
// 			builder.Cmds.Append(arg)
// 			i++
// 			continue
// 		}

// 		switch arg {
// 		// Boolean flags
// 		case "--dryrun":
// 			builder.Dryrun = true
// 			i++
// 		case "--verbose":
// 			builder.Verbose = true
// 			i++
// 		case "--pull":
// 			builder.DoPull = true
// 			i++
// 		case "--daemon":
// 			builder.Daemon = true
// 			i++
// 		case "--keep-alive":
// 			builder.Keepalive = true
// 			i++
// 		case "--dind":
// 			builder.Dind = true
// 			i++
// 		case "--silence-build":
// 			builder.SilenceBuild = true
// 			i++

// 		// Value flags
// 		case "--config":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--config requires a path")
// 			}
// 			builder.ConfigFile = args[i+1]
// 			i += 2
// 		case "--workspace":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--workspace requires a path")
// 			}
// 			builder.WorkspacePath = args[i+1]
// 			i += 2
// 		case "--image":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--image requires a value")
// 			}
// 			builder.ImageName = args[i+1]
// 			i += 2
// 		case "--variant":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--variant requires a value")
// 			}
// 			builder.Variant = args[i+1]
// 			i += 2
// 		case "--version":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--version requires a value")
// 			}
// 			builder.Version = args[i+1]
// 			i += 2
// 		case "--dockerfile":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--dockerfile requires a path")
// 			}
// 			builder.DockerFile = args[i+1]
// 			i += 2
// 		case "--name":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--name requires a value")
// 			}
// 			builder.ContainerName = args[i+1]
// 			i += 2
// 		case "--port":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--port requires a value")
// 			}
// 			builder.WorkspacePort = args[i+1]
// 			i += 2
// 		case "--env-file":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--env-file requires a path")
// 			}
// 			builder.ContainerEnvFile = args[i+1]
// 			i += 2

// 		// Build args (special handling - adds to list)
// 		case "--build-arg":
// 			if i+1 >= len(args) {
// 				return fmt.Errorf("--build-arg requires a value")
// 			}
// 			builder.BuildArgs.Append("--build-arg", args[i+1])
// 			i += 2

// 		// Command separator
// 		case "--":
// 			parsingCmds = true
// 			i++

// 		// Unknown flags or run args
// 		default:
// 			// Unknown arguments go to RUN_ARGS
// 			builder.RunArgs.Append(arg)
// 			i++
// 		}
// 	}

// 	return nil
// }
