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

// InitializeAppContext creates an AppContext with default values matching workspace Main()
func InitializeAppContext(version string, boundary InitializeAppContextBoundary) appctx.AppContext {
	// Initialize config and context
	config := appctx.AppConfig{}
	context := appctx.AppContextBuilder{
		Config: config,
	}

	args := boundary.ArgList()

	// Set default values and effective constants
	context.PrebuildRepo = "nawaman/workspace"
	context.WsVersion = version
	context.SetupsDir = "/opt/workspace/setups"
	context.ScriptName = getScriptName(args)
	context.ScriptDir = getScriptDir(args)
	context.Version = context.Config.Version.ValueOr(context.WsVersion)
	context.Config.HostUID = boundary.GetHostUID()
	context.Config.HostGID = boundary.GetHostGID()
	context.Config.Timezone = boundary.DetectTimezone()

	// First pass to read important flags and value: --dryrun, --verbose, --config
	configExplicitlySet := false
	readVerboseDryrunConfigFileAndWorkspace(boundary, &context, &configExplicitlySet)

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
	readFromToml(boundary, &context, configExplicitlySet)
	readFromArgs(boundary, &context, ilist.NewListFromSlice(args.Slice()[1:]))

	if context.Config.ProjectName == "" {
		context.Config.ProjectName = getProjectName(context.Config.Workspace.ValueOr("."))
	}
	if context.Config.Name == "" {
		context.Config.Name = context.Config.ProjectName
	}

	// Sync list fields from Config to Builder
	// We wrap the flat string list from Config into a single group in the nested list structure

	if len(context.Config.Cmds.Slice()) > 0 {
		var group ilist.List[string] = ilist.NewListFromSlice(context.Config.Cmds.Slice())
		context.Cmds = ilist.NewAppendableListFrom(group)
	} else {
		context.Cmds = ilist.NewAppendableList[ilist.List[string]]()
	}

	if len(context.Config.RunArgs.Slice()) > 0 {
		var group ilist.List[string] = ilist.NewListFromSlice(context.Config.RunArgs.Slice())
		context.RunArgs = ilist.NewAppendableListFrom(group)
	} else {
		context.RunArgs = ilist.NewAppendableList[ilist.List[string]]()
	}

	if len(context.Config.CommonArgs.Slice()) > 0 {
		var group ilist.List[string] = ilist.NewListFromSlice(context.Config.CommonArgs.Slice())
		context.CommonArgs = ilist.NewAppendableListFrom(group)
	} else {
		context.CommonArgs = ilist.NewAppendableList[ilist.List[string]]()
	}

	if len(context.Config.BuildArgs.Slice()) > 0 {
		var group ilist.List[string] = ilist.NewListFromSlice(context.Config.BuildArgs.Slice())
		context.BuildArgs = ilist.NewAppendableListFrom(group)
	} else {
		context.BuildArgs = ilist.NewAppendableList[ilist.List[string]]()
	}

	return context.Build()
}

// getProjectName extracts a sanitized project name from the workspace path
func getProjectName(workspacePath string) string {
	// Resolve to absolute path to handle relative paths like ".."
	if absPath, err := filepath.Abs(workspacePath); err == nil {
		workspacePath = absPath
	}

	// Get the base name of the path
	baseName := filepath.Base(workspacePath)

	// Sanitize: replace non-alphanumeric characters with underscores
	// This matches the workspace project_name function behavior
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

		// Skipped -- already processed
		case "--config":
			i += 2
		case "--workspace":
			i += 2
		case "--verbose":
			i++
		case "--dryrun":
			i++

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
			cfg.Version = nillable.NewNillableString(v)
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
// If configExplicitlySet is true, the config file must exist. Otherwise, it's optional.
func readFromToml(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, configExplicitlySet bool) {
	if !context.Config.Config.IsSet() {
		return
	}

	runPreserveWorkspaceAndConfig(context, func() {
		cfgFile := context.Config.Config.ValueOrPanic()
		if _, err := os.Stat(cfgFile); os.IsNotExist(err) {
			// Only panic if the config file was explicitly set by the user
			if configExplicitlySet {
				panic(fmt.Errorf("config file %s does not exist", cfgFile))
			}
			// If it's the default config file, just skip reading it
			return
		}
		if err := appctx.ReadFromToml(cfgFile, &context.Config); err != nil {
			panic(fmt.Errorf("failed to read toml config: %w", err))
		}
	})
}

// readVerboseDryrunConfigFileAndWorkspace parses arguments looking for config file and verbosity settings.
// This allows loading configuration before full argument parsing.
// It sets configExplicitlySet to true if --config was provided by the user.
func readVerboseDryrunConfigFileAndWorkspace(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, configExplicitlySet *bool) {
	args := boundary.ArgList()
	for i := 0; i < args.Length(); {
		arg := args.At(i)
		switch arg {
		case "--config":
			value, err := needValue(args, i, arg)
			if err != nil {
				panic(fmt.Errorf("error parsing --config: %w", err))
			}
			// Resolve relative paths to absolute paths
			if !filepath.IsAbs(value) {
				if absPath, err := filepath.Abs(value); err == nil {
					value = absPath
				}
			}
			context.Config.Config = nillable.NewNillableString(value)
			*configExplicitlySet = true
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
