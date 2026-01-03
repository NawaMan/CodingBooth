package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/nawaman/workspace/src/pkg/appctx"
)

// version is set at build time via -ldflags "-X main.version=$(cat version.txt)"
var version = "dev" // fallback if not set at build time

func main() {
	// Check for commands
	if len(os.Args) > 1 {
		command := os.Args[1]

		switch command {
		case "version":
			showVersion()
			return
		case "--help", "-h", "help":
			showHelp()
			return
		case "run":
			runWorkspace()
			return
		default:
			// If it starts with --, treat as run with options
			if len(command) > 0 && command[0] == '-' {
				runWorkspace()
				return
			}
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
			fmt.Fprintln(os.Stderr, "Use 'workspace help' for usage information")
			os.Exit(1)
		}
	}

	// No arguments: run workspace
	runWorkspace()
}

func showVersion() {
	banner := `__      __       _    ___                   
\ \    / /__ _ _| |__/ __|_ __  __ _ __ ___ 
 \ \/\/ / _ \ '_| / /\__ \ '_ \/ _` + "`" + ` / _/ -_)
  \_/\_/\___/_| |_\_\|___/ .__/\__,_\__\___|
                         |_|                `
	fmt.Println(banner)
	fmt.Printf("WorkSpace: %s\n", version)
}

func showHelp() {
	scriptName := "workspace"
	if len(os.Args) > 0 {
		scriptName = os.Args[0]
	}

	fmt.Printf(`%s — launch a Docker-based development workspace

USAGE:
  %s <action> [options]
  %s [run options] [--] [command ...]

ACTIONS:
  version                Print the workspace version
  help                   Show this help and exit
  run                    Run the workspace (default if no action given)

GENERAL:
  --verbose              Print extra debugging information
  --dryrun               Print docker commands without executing them
  --pull                 Always pull the image, even if it exists locally
                         (default behavior is to check if the image exists
                          locally and pull it only if it is missing)
  --daemon               Run the workspace container in the background
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST
  --keep-alive           Do not remove the container when stopped
  --skip-main            Do not run Main; load functions only (for testing)
  --config <file>        Load defaults from a config shell file (default: ./ws--config.sh)
  --workspace <path>     Host workspace path to mount at /home/coder/workspace

IMAGE SELECTION (precedence: --image > --dockerfile > prebuilt):
  --image <name>         Use an existing local or remote image (e.g. repo/name:tag)
                         The script will check if the image exists locally and
                         pull it only if it is missing (unless --pull is used).
  --dockerfile <path>    Build locally from Dockerfile (file or directory)
                         If a directory is provided, it must contain ws--Dockerfile.
  --variant <name>       Prebuilt variant:
                           container | ide-notebook | ide-codeserver
                           desktop-xfce | desktop-kde
                         Aliases:
                           notebook | codeserver | xfce | kde
  --version <tag>        Prebuilt version tag (default: latest)

BUILD OPTIONS (only when using --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure
  NOTE: Build args are ignored when using prebuilt images or --image.

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from workspace directory)
  --port <n|RANDOM|NEXT> Host port → container 10000
                         n      : any valid TCP port (1–65535)
                         RANDOM : pick a random free port ≥ 10000
                         NEXT   : pick the next available free port ≥ 10000
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable auto-detection of <workspace>/.env

COMMANDS:
  All arguments after '--' are executed *inside* the container instead of
  starting the default workspace service. Example:
    %s -- -- bash -lc "echo hi"

NOTES:
  - Default image behavior:
        The script checks whether the image exists locally.
        If it is missing, it will be pulled automatically.
        Use --pull to always pull, even if the image already exists.

  - If --env-file is not provided, a <workspace>/.env file will be used when present.
    Specify '--env-file none' to disable this behavior.

  - In daemon mode, do not pass commands after '--'. Stop the container with:
        docker stop <container-name>

  - With --dind, a docker:dind sidecar runs on a private network and the main
    container uses DOCKER_HOST=tcp://<sidecar>:2375.

EXAMPLES:
  # Prebuilt, foreground
  %s --variant container --version latest --workspace /path/to/ws

  # Local build from Dockerfile
  %s --dockerfile ./Dockerfile --workspace . --build-arg FOO=bar

  # Daemon mode with random port
  %s --daemon --variant codeserver --port RANDOM

  # Run a one-off command inside the image
  %s --image my/image:tag -- env | sort

  # Disable automatic .env usage
  %s --env-file none --variant notebook
`, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName, scriptName)
}

func runWorkspace() {
	ctx := initializeAppContext()

	// TODO: Load config file
	// TODO: Parse arguments
	// TODO: Execute workspace pipeline

	// Temporary: show what we've initialized (always show for now)
	fmt.Printf("Initialized AppContext:\n")
	fmt.Printf("  WsVersion: %s\n", ctx.WsVersion())
	fmt.Printf("  ScriptName: %s\n", ctx.ScriptName())
	fmt.Printf("  ScriptDir: %s\n", ctx.ScriptDir())
	fmt.Printf("  WorkspacePath: %s\n", ctx.WorkspacePath())
	fmt.Printf("  ProjectName: %s\n", ctx.ProjectName())
	fmt.Printf("  HostUID: %s\n", ctx.HostUID())
	fmt.Printf("  HostGID: %s\n", ctx.HostGID())
	fmt.Printf("  Timezone: %s\n", ctx.Timezone())
	fmt.Printf("  Variant: %s\n", ctx.Variant())
	fmt.Printf("  Daemon: %v\n", ctx.Daemon())
	fmt.Printf("  Verbose: %v\n", ctx.Verbose())
	fmt.Printf("  WorkspacePort: %s\n", ctx.WorkspacePort())
	fmt.Printf("  ContainerName: %s\n", ctx.ContainerName())
	if ctx.BuildArgs().Length() > 0 {
		fmt.Printf("  BuildArgs: %v\n", ctx.BuildArgs().Slice())
	}
	if ctx.RunArgs().Length() > 0 {
		fmt.Printf("  RunArgs: %v\n", ctx.RunArgs().Slice())
	}
	if ctx.Cmds().Length() > 0 {
		fmt.Printf("  Cmds: %v\n", ctx.Cmds().Slice())
	}

	fmt.Println("✅ AppContext initialized successfully")
	os.Exit(0)
}

// initializeAppContext creates an AppContext with default values matching workspace.sh Main()
func initializeAppContext() appctx.AppContext {
	builder := appctx.NewAppContextBuilder(version)

	builder.ScriptName = getScriptName()
	builder.ScriptDir = getScriptDir()
	builder.LibDir = filepath.Join(builder.ScriptDir, "libs")
	builder.WorkspacePath = getCurrentPath()
	builder.ProjectName = getProjectName(builder.WorkspacePath)
	builder.ConfigFile = "./ws-config.toml"
	builder.HostUID = getHostUID()
	builder.HostGID = getHostGID()
	builder.Timezone = detectTimezone()

	// Load config file (overrides defaults)
	if err := loadConfig(builder.ConfigFile, builder); err != nil {
		fmt.Fprintf(os.Stderr, "Error loading config: %v\n", err)
		os.Exit(1)
	}

	// Parse command-line arguments (overrides config)
	if err := parseArgs(os.Args[1:], builder); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	return builder.Build()
}

// loadConfig loads TOML configuration from the specified file into the builder.
// If the file doesn't exist, this is not an error (config is optional).
func loadConfig(configFile string, builder *appctx.AppContextBuilder) error {
	// Check if config file exists
	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		// Config file is optional
		return nil
	}

	// Decode TOML file into builder
	if _, err := toml.DecodeFile(configFile, builder); err != nil {
		return fmt.Errorf("failed to parse config file %s: %w", configFile, err)
	}

	// Convert TOML-decoded slices to AppendableList instances
	builder.ApplySlicesToLists()

	return nil
}

// parseArgs parses command-line arguments and applies them to the builder.
// This matches the behavior of workspace.sh ParseArgs function.
func parseArgs(args []string, builder *appctx.AppContextBuilder) error {
	parsingCmds := false
	i := 0

	for i < len(args) {
		arg := args[i]

		// After --, everything is a command
		if parsingCmds {
			builder.Cmds.Append(arg)
			i++
			continue
		}

		switch arg {
		// Boolean flags
		case "--dryrun":
			builder.Dryrun = true
			i++
		case "--verbose":
			builder.Verbose = true
			i++
		case "--pull":
			builder.DoPull = true
			i++
		case "--daemon":
			builder.Daemon = true
			i++
		case "--keep-alive":
			builder.Keepalive = true
			i++
		case "--dind":
			builder.Dind = true
			i++
		case "--silence-build":
			builder.SilenceBuild = true
			i++

		// Value flags
		case "--config":
			if i+1 >= len(args) {
				return fmt.Errorf("--config requires a path")
			}
			builder.ConfigFile = args[i+1]
			i += 2
		case "--workspace":
			if i+1 >= len(args) {
				return fmt.Errorf("--workspace requires a path")
			}
			builder.WorkspacePath = args[i+1]
			i += 2
		case "--image":
			if i+1 >= len(args) {
				return fmt.Errorf("--image requires a value")
			}
			builder.ImageName = args[i+1]
			i += 2
		case "--variant":
			if i+1 >= len(args) {
				return fmt.Errorf("--variant requires a value")
			}
			builder.Variant = args[i+1]
			i += 2
		case "--version":
			if i+1 >= len(args) {
				return fmt.Errorf("--version requires a value")
			}
			builder.Version = args[i+1]
			i += 2
		case "--dockerfile":
			if i+1 >= len(args) {
				return fmt.Errorf("--dockerfile requires a path")
			}
			builder.DockerFile = args[i+1]
			i += 2
		case "--name":
			if i+1 >= len(args) {
				return fmt.Errorf("--name requires a value")
			}
			builder.ContainerName = args[i+1]
			i += 2
		case "--port":
			if i+1 >= len(args) {
				return fmt.Errorf("--port requires a value")
			}
			builder.WorkspacePort = args[i+1]
			i += 2
		case "--env-file":
			if i+1 >= len(args) {
				return fmt.Errorf("--env-file requires a path")
			}
			builder.ContainerEnvFile = args[i+1]
			i += 2

		// Build args (special handling - adds to list)
		case "--build-arg":
			if i+1 >= len(args) {
				return fmt.Errorf("--build-arg requires a value")
			}
			builder.BuildArgs.Append("--build-arg", args[i+1])
			i += 2

		// Command separator
		case "--":
			parsingCmds = true
			i++

		// Unknown flags or run args
		default:
			// Unknown arguments go to RUN_ARGS
			builder.RunArgs.Append(arg)
			i++
		}
	}

	return nil
}

// getCurrentPath returns the current working directory, handling MSYS/Git Bash on Windows
func getCurrentPath() string {
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting current directory: %v\n", err)
		os.Exit(1)
	}

	if runtime.GOOS == "windows" {
		return cwd
	}

	return cwd
}

// getScriptName returns the base name of the executable
func getScriptName() string {
	if len(os.Args) > 0 {
		return filepath.Base(os.Args[0])
	}
	return "workspace"
}

// getScriptDir returns the directory containing the executable
func getScriptDir() string {
	if len(os.Args) == 0 {
		return "."
	}

	exePath := os.Args[0]

	// Get absolute path
	absPath, err := filepath.Abs(exePath)
	if err != nil {
		return filepath.Dir(exePath)
	}

	// Resolve symlinks
	realPath, err := filepath.EvalSymlinks(absPath)
	if err != nil {
		return filepath.Dir(absPath)
	}

	return filepath.Dir(realPath)
}

// getProjectName extracts a sanitized project name from the workspace path
func getProjectName(workspacePath string) string {
	// Get the base name of the path
	baseName := filepath.Base(workspacePath)

	// Sanitize: replace non-alphanumeric characters with underscores
	// This matches the workspace.sh project_name function behavior
	var result strings.Builder
	for _, ch := range baseName {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			result.WriteRune(ch)
		} else {
			result.WriteRune('_')
		}
	}

	sanitized := result.String()
	if sanitized == "" {
		return "workspace"
	}

	return sanitized
}

// getHostUID returns the current user's UID as a string
func getHostUID() string {
	if runtime.GOOS == "windows" {
		// Windows doesn't have UIDs, return a default
		return "1000"
	}

	// Use id -u command
	cmd := exec.Command("id", "-u")
	output, err := cmd.Output()
	if err != nil {
		return "1000" // fallback
	}

	return strings.TrimSpace(string(output))
}

// getHostGID returns the current user's GID as a string
func getHostGID() string {
	if runtime.GOOS == "windows" {
		// Windows doesn't have GIDs, return a default
		return "1000"
	}

	// Use id -g command
	cmd := exec.Command("id", "-g")
	output, err := cmd.Output()
	if err != nil {
		return "1000" // fallback
	}

	return strings.TrimSpace(string(output))
}

// detectTimezone detects the system timezone
func detectTimezone() string {
	// Try to get timezone from environment
	if tz := os.Getenv("TZ"); tz != "" {
		return tz
	}

	// Use Go's time package to detect local timezone
	now := time.Now()
	zone, _ := now.Zone()

	// If we can get the IANA timezone name, use it
	if loc := now.Location(); loc != nil && loc.String() != "Local" {
		return loc.String()
	}

	// Fallback to zone abbreviation (e.g., "EST", "PST")
	if zone != "" {
		return zone
	}

	// Ultimate fallback
	return "UTC"
}
