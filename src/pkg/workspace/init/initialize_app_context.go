package init

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"github.com/nawaman/workspace/src/pkg/nillable"
)

// InitializeAppContext creates an AppContext with default values matching workspace.sh Main()
func InitializeAppContext(boundary InitializeAppContextBoundary) appctx.AppContext {
	// Initialize config and context
	config := appctx.AppConfig{}
	context := appctx.AppContextBuilder{
		Config: config,
	}

	args := boundary.ArgList()

	// Set default values and effective constants
	context.ScriptName = getScriptName(args)
	context.ScriptDir = getScriptDir(args)
	context.Config.HostUID = boundary.GetHostUID()
	context.Config.HostGID = boundary.GetHostGID()
	context.Config.Timezone = boundary.DetectTimezone()

	// First pass to read important flags and value: --dryrun, --verbose, --config
	readVerboseDryrunConfigFileAndWorkspace(boundary, &context)

	// Set additional values that is derived from other values
	context.LibDir = filepath.Join(context.ScriptDir, "libs")
	if !context.Config.Workspace.IsSet() {
		context.Config.Workspace = nillable.NewNillableString(boundary.GetCurrentPath())
	}
	if !context.Config.Config.IsSet() {
		workspace := context.Config.Workspace.ValueOr("")
		context.Config.Config = nillable.NewNillableString(filepath.Join(workspace, "ws--config.toml"))
	}

	readFromEnvVars(boundary, &context)
	readFromToml(boundary, &context)
	readFromArgs(boundary, &context, ilist.NewListFromSlice(args.Slice()[1:]))

	if context.Config.ProjectName == "" {
		context.Config.ProjectName = getProjectName(context.Config.Workspace.ValueOr(""))
	}

	// Sync list fields from Config to Builder
	context.Cmds = ilist.NewAppendableListFrom(context.Config.Cmds.Slice()...)
	context.RunArgs = ilist.NewAppendableListFrom(context.Config.RunArgs.Slice()...)
	context.CommonArgs = ilist.NewAppendableListFrom(context.Config.CommonArgs.Slice()...)
	context.BuildArgs = ilist.NewAppendableListFrom(context.Config.BuildArgs.Slice()...)

	return context.Build()
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

// getScriptDir returns the directory containing the executable
func getScriptDir(args ilist.List[string]) string {
	if args.Length() == 0 {
		return "."
	}

	exePath := args.At(0)

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

// getScriptName returns the base name of the executable
func getScriptName(args ilist.List[string]) string {
	if args.Length() > 0 {
		return filepath.Base(args.At(0))
	}
	return "workspace"
}

func needValue(args ilist.List[string], i int, flag string) (string, error) {
	// matches bash: [[ -n "${2:-}" ]]
	if i+1 >= args.Length() || args.At(i+1) == "" {
		return "", fmt.Errorf("error: %s requires a value", flag)
	}
	return args.At(i + 1), nil
}

// parseArgs ports your bash ParseArgs() logic.
// Pass in os.Args[1:].
func parseArgs(args ilist.List[string], cfg *appctx.AppConfig) error {
	parsingCmds := false

	// Work on local mutable copies (avoids O(n^2) rebuilding immutable lists)
	runArgs := cfg.RunArgs.Slice()
	buildArgs := cfg.BuildArgs.Slice()
	cmds := cfg.Cmds.Slice()

	for i := 0; i < args.Length(); {
		arg := args.At(i)

		if parsingCmds {
			cmds = append(cmds, arg)
			i++
			continue
		}

		switch arg {

		// Simple flags
		case "--daemon":
			cfg.Daemon = true
			i++

		case "--keep-alive":
			cfg.KeepAlive = true
			i++

		case "--dind":
			cfg.Dind = true
			i++

		case "--pull":
			cfg.Pull = true
			i++

		case "--silence-build":
			cfg.SilenceBuild = true
			i++

		// Image selection
		case "--image":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Image = v
			i += 2

		case "--variant":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Variant = v
			i += 2

		case "--version":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Version = v
			i += 2

		case "--dockerfile":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Dockerfile = v
			i += 2

		// Build
		case "--build-arg":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			// matches bash: BUILD_ARGS+=(--build-arg "$2")
			buildArgs = append(buildArgs, "--build-arg", v)
			i += 2

		// Run
		case "--name":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Name = v
			i += 2

		case "--port":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Port = v
			i += 2

		case "--env-file":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.EnvFile = v
			i += 2

		case "--":
			// everything after goes to cmds
			parsingCmds = true
			i++

		default:
			// matches bash: RUN_ARGS+=("$1")
			runArgs = append(runArgs, arg)
			i++
		}
	}

	// Re-freeze lists once, at the end
	cfg.RunArgs = ilist.SemicolonStringList{List: ilist.NewList(runArgs...)}
	cfg.BuildArgs = ilist.SemicolonStringList{List: ilist.NewList(buildArgs...)}
	cfg.Cmds = ilist.SemicolonStringList{List: ilist.NewList(cmds...)}

	return nil
}

// readFromArgs parses command-line arguments and populates the config (overriding existing values).
// It preserves verbose, dryrun, workspace, and config.
func readFromArgs(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, args ilist.List[string]) {
	runPreserveWorkspaceAndConfig(context, func() {
		if err := parseArgs(args, &context.Config); err != nil {
			panic(fmt.Errorf("failed to parse args: %w", err))
		}
	})
}

// readFromEnvVars reads configuration from environment variables and populates the config (overriding existing values).
// The function preserve the verbose, dryrun and config values.
func readFromEnvVars(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder) {
	runPreserveWorkspaceAndConfig(context, func() {
		if err := boundary.PopulateAppConfigFromEnvVars(&context.Config); err != nil {
			panic(fmt.Errorf("failed to populate app config from env vars: %w", err))
		}
	})
}

// readFromToml reads configuration from a TOML file and populates the config (overriding existing values).
// It preserves verbose, dryrun, workspace, and config.
func readFromToml(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder) {
	if !context.Config.Config.IsSet() {
		return
	}

	runPreserveWorkspaceAndConfig(context, func() {
		cfgFile := context.Config.Config.ValueOrPanic()
		if _, err := os.Stat(cfgFile); os.IsNotExist(err) {
			return
		}
		if err := appctx.ReadFromToml(cfgFile, &context.Config); err != nil {
			panic(fmt.Errorf("failed to read toml config: %w", err))
		}
	})
}

// readVerboseDryrunConfigFileAndWorkspace parses arguments looking for config file and verbosity settings.
// This allows loading configuration before full argument parsing.
func readVerboseDryrunConfigFileAndWorkspace(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder) {
	args := boundary.ArgList()
	for i := 0; i < args.Length(); {
		arg := args.At(i)
		switch arg {
		case "--config":
			value, err := needValue(args, i, arg)
			if err != nil {
				panic(fmt.Errorf("error parsing --config: %w", err))
			}
			context.Config.Config = nillable.NewNillableString(value)
			i += 2

		case "--workspace":
			value, err := needValue(args, i, arg)
			if err != nil {
				panic(fmt.Errorf("error parsing --workspace: %w", err))
			}
			context.Config.Workspace = nillable.NewNillableString(value)
			i += 2

		case "--verbose":
			context.Config.Verbose = nillable.NewNillableBool(true)
			i++

		case "--dryrun":
			context.Config.Dryrun = nillable.NewNillableBool(true)
			i++

		default:
			i++
		}
	}
}

func runPreserveWorkspaceAndConfig(context *appctx.AppContextBuilder, fn func()) {
	configFile := context.Config.Config
	workspace := context.Config.Workspace

	fn()

	if configFile.IsSet() {
		context.Config.Config = configFile
	}
	if workspace.IsSet() {
		context.Config.Workspace = workspace
	}
}
