// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"golang.org/x/term"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/defaults"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

// InitializeAppContext creates an AppContext with default values matching booth Main()
func InitializeAppContext(version string, boundary InitializeAppContextBoundary) appctx.AppContext {
	// Initialize config and context
	config := appctx.AppConfig{}
	context := appctx.AppContextBuilder{
		Config: config,
	}

	args := boundary.ArgList()

	// Set default values and effective constants
	context.PrebuildRepo = "nawaman/codingbooth"
	context.CbVersion = version
	context.SetupsDir = "/opt/codingbooth/setups"
	context.ScriptName = getScriptName(args)
	context.ScriptDir = getScriptDir(args)
	context.Version = context.Config.Version.ValueOr(context.CbVersion)
	context.Config.HostUID = boundary.GetHostUID()
	context.Config.HostGID = boundary.GetHostGID()
	context.Config.Timezone = boundary.DetectTimezone()

	// First pass to read important flags and value: --dryrun, --verbose, --config and --code
	configExplicitlySet := false
	readVerboseDryrunConfigFileAndCode(boundary, &context, &configExplicitlySet)

	// Set additional values that is derived from other values
	context.LibDir = filepath.Join(context.ScriptDir, "libs")
	if !context.Config.Code.IsSet() {
		context.Config.Code = nillable.NewNillableString(boundary.GetCurrentPath())
	}
	if !context.Config.Config.IsSet() {
		codePath := context.Config.Code.ValueOr("")
		configFile := filepath.Join(codePath, ".booth", "config.toml")
		if fileExists(configFile) {
			context.Config.Config = nillable.NewNillableString(configFile)
		}
	}

	readFromEnvVars(boundary, &context)
	readFromToml(boundary, &context, configExplicitlySet)
	readFromArgs(boundary, &context, ilist.NewListFromSlice(args.Slice()[1:]))
	validateConfig(&context.Config)
	resolvePassword(&context.Config)

	if context.Config.ProjectName == "" {
		context.Config.ProjectName = getProjectName(context.Config.Code.ValueOr("."))
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

func validateConfig(config *appctx.AppConfig) {
	if err := validateSandboxConfig(config); err != nil {
		panic(err)
	}
}

const (
	defaultSandboxAllowlistPath = ".booth/sandbox/allowlist.txt"
	defaultSandboxPolicyPath    = ".booth/sandbox/envoy.yaml"
)

func validateSandboxConfig(config *appctx.AppConfig) error {
	// --sandboxed enables sandbox defaults.
	if config.Sandbox {
		if config.SandboxMode == "" {
			config.SandboxMode = "envoy"
		}
		if config.SandboxEnforcement == "" {
			config.SandboxEnforcement = "iptables"
		}
	}

	config.SandboxMode = strings.ToLower(strings.TrimSpace(config.SandboxMode))
	config.SandboxEnforcement = strings.ToLower(strings.TrimSpace(config.SandboxEnforcement))
	config.SandboxAllowlistFile = strings.TrimSpace(config.SandboxAllowlistFile)
	config.SandboxPolicyFile = strings.TrimSpace(config.SandboxPolicyFile)
	for i := range config.SandboxAllowlist {
		config.SandboxAllowlist[i] = strings.TrimSpace(config.SandboxAllowlist[i])
	}

	if err := applySandboxPolicyDefaults(config); err != nil {
		return err
	}

	if config.SandboxMode != "" &&
		config.SandboxMode != "none" &&
		config.SandboxMode != "envoy" &&
		config.SandboxMode != "squid" &&
		config.SandboxMode != "tinyproxy" {
		return fmt.Errorf("invalid sandbox-mode %q (supported: none, envoy, squid, tinyproxy)", config.SandboxMode)
	}

	if config.SandboxEnforcement != "" &&
		config.SandboxEnforcement != "none" &&
		config.SandboxEnforcement != "iptables" &&
		config.SandboxEnforcement != "nftables" {
		return fmt.Errorf("invalid sandbox-enforcement %q (supported: none, iptables, nftables)", config.SandboxEnforcement)
	}

	if config.SandboxPolicyFile != "" && len(config.SandboxAllowlist) > 0 {
		return fmt.Errorf("sandbox-allowlist cannot be used with sandbox-policy-file")
	}

	if config.SandboxAllowlistFile != "" && config.SandboxPolicyFile != "" {
		return fmt.Errorf("sandbox-allowlist-file and sandbox-policy-file are mutually exclusive")
	}

	if config.SandboxAllowlistFile != "" {
		if err := ensureRegularFile(resolvePathFromCodeDir(config.Code.ValueOr(""), config.SandboxAllowlistFile)); err != nil {
			return fmt.Errorf("invalid sandbox-allowlist-file: %w", err)
		}
	}

	if config.SandboxPolicyFile != "" {
		if err := ensureRegularFile(resolvePathFromCodeDir(config.Code.ValueOr(""), config.SandboxPolicyFile)); err != nil {
			return fmt.Errorf("invalid sandbox-policy-file: %w", err)
		}
	}

	return nil
}

func applySandboxPolicyDefaults(config *appctx.AppConfig) error {
	if !config.Sandbox {
		return nil
	}
	if config.SandboxAllowlistFile != "" || config.SandboxPolicyFile != "" {
		return nil
	}

	codeDir := config.Code.ValueOr("")
	if codeDir == "" {
		return fmt.Errorf("sandbox requires a code directory to resolve sandbox policy")
	}

	allowlistPath := filepath.Join(codeDir, defaultSandboxAllowlistPath)
	policyPath := filepath.Join(codeDir, defaultSandboxPolicyPath)
	allowlistExists := fileExists(allowlistPath)
	policyExists := fileExists(policyPath)

	if allowlistExists && policyExists {
		return fmt.Errorf("both %q and %q exist; choose only one", defaultSandboxAllowlistPath, defaultSandboxPolicyPath)
	}
	if allowlistExists {
		config.SandboxAllowlistFile = defaultSandboxAllowlistPath
		return nil
	}
	if policyExists {
		config.SandboxPolicyFile = defaultSandboxPolicyPath
		return nil
	}

	if err := os.MkdirAll(filepath.Dir(allowlistPath), 0o755); err != nil {
		return fmt.Errorf("failed to create default allowlist dir: %w", err)
	}
	if err := os.WriteFile(allowlistPath, []byte(defaults.ExampleAllowlist), 0o644); err != nil {
		return fmt.Errorf("failed to write default allowlist: %w", err)
	}
	config.SandboxAllowlistFile = defaultSandboxAllowlistPath
	return nil
}

func resolvePathFromCodeDir(codeDir, path string) string {
	if filepath.IsAbs(path) || codeDir == "" {
		return path
	}
	return filepath.Join(codeDir, path)
}

func ensureRegularFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("file %q does not exist", path)
	}
	if info.IsDir() {
		return fmt.Errorf("%q is a directory", path)
	}
	return nil
}

// getProjectName extracts a sanitized project name from the code path
func getProjectName(codePath string) string {
	// Resolve to absolute path to handle relative paths like ".."
	if absPath, err := filepath.Abs(codePath); err == nil {
		codePath = absPath
	}

	// Get the base name of the path
	baseName := filepath.Base(codePath)

	// Sanitize: replace non-alphanumeric characters with hyphens (kebab-case)
	// This creates Docker-friendly container names
	var result strings.Builder
	for _, ch := range baseName {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
			result.WriteRune(ch)
		} else {
			result.WriteRune('-')
		}
	}

	sanitized := result.String()
	if sanitized == "" {
		return "booth"
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
	return "codingbooth"
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
		case "--code":
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

		case "--sandboxed":
			cfg.Sandbox = true
			i++
		case "--sandbox":
			// Backward compatibility alias.
			cfg.Sandbox = true
			i++

		case "--pull":
			cfg.Pull = true
			i++

		case "--silence-build":
			cfg.SilenceBuild = true
			i++

		case "--writable-booth":
			cfg.WritableBooth = true
			i++


		case "--public":
			cfg.Public = true
			i++

		case "--tls-cert":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.TLSCert = v
			i += 2

		case "--tls-key":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.TLSKey = v
			i += 2

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

		case "--boothfile":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Boothfile = v
			i += 2

		case "--strict":
			cfg.Strict = true
			i++

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

		case "--startup":
			v, err := needValue(args, i, arg)
			if err != nil {
				return err
			}
			cfg.Startup = v
			i += 2

		case "--":
			// everything after goes to cmds, overriding any cmds from config
			cmds = []string{} // Clear existing cmds so CLI overrides config
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
// It preserves verbose, dryrun, code, and config.
func readFromArgs(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, args ilist.List[string]) {
	runPreserveCodeAndConfig(context, func() {
		if err := parseArgs(args, &context.Config); err != nil {
			panic(fmt.Errorf("failed to parse args: %w", err))
		}
	})
}

// readFromEnvVars reads configuration from environment variables and populates the config (overriding existing values).
// The function preserve the verbose, dryrun and config values.
func readFromEnvVars(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder) {
	runPreserveCodeAndConfig(context, func() {
		if err := boundary.PopulateAppConfigFromEnvVars(&context.Config); err != nil {
			panic(fmt.Errorf("failed to populate app config from env vars: %w", err))
		}
	})
}

// readFromToml reads configuration from a TOML file and populates the config (overriding existing values).
// It preserves verbose, dryrun, code, and config.
// If configExplicitlySet is true, the config file must exist. Otherwise, it's optional.
func readFromToml(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, configExplicitlySet bool) {
	if !context.Config.Config.IsSet() {
		return
	}

	runPreserveCodeAndConfig(context, func() {
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

// readVerboseDryrunConfigFileAndCode parses arguments looking for config file and verbosity settings.
// This allows loading configuration before full argument parsing.
// It sets configExplicitlySet to true if --config was provided by the user.
func readVerboseDryrunConfigFileAndCode(boundary InitializeAppContextBoundary, context *appctx.AppContextBuilder, configExplicitlySet *bool) {
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

		case "--code":
			value, err := needValue(args, i, arg)
			if err != nil {
				panic(fmt.Errorf("error parsing --code: %w", err))
			}
			context.Config.Code = nillable.NewNillableString(value)
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

func runPreserveCodeAndConfig(context *appctx.AppContextBuilder, fn func()) {
	configFile := context.Config.Config
	code := context.Config.Code

	fn()

	if configFile.IsSet() {
		context.Config.Config = configFile
	}
	if code.IsSet() {
		context.Config.Code = code
	}
}

// fileExists checks if a file exists and is not a directory
func fileExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}

// resolvePassword populates config.Password when --public is set.
// Priority: .booth/.booth.password file → interactive stdin prompt → error.
func resolvePassword(config *appctx.AppConfig) {
	if !config.Public {
		return
	}

	// Priority 1: .booth/.booth.password file
	codeDir := config.Code.ValueOr("")
	if codeDir != "" {
		passwordFile := filepath.Join(codeDir, ".booth", ".booth.password")
		if fileExists(passwordFile) {
			if err := validatePasswordFile(passwordFile, codeDir); err != nil {
				panic(err)
			}
			content, err := os.ReadFile(passwordFile)
			if err != nil {
				panic(fmt.Errorf("failed to read password file %q: %w", passwordFile, err))
			}
			password := strings.TrimSpace(string(content))
			if password == "" {
				panic(fmt.Errorf("password file %q is empty", passwordFile))
			}
			config.Password = password
			return
		}
	}

	// Priority 2: interactive stdin prompt
	password, err := readPasswordFromStdin()
	if err != nil {
		panic(fmt.Errorf("--public requires a password but none could be read: %w", err))
	}
	password = strings.TrimSpace(password)
	if password == "" {
		panic(fmt.Errorf("--public requires a password but received empty input"))
	}
	config.Password = password
}

// readPasswordFromStdin reads a password from stdin.
// If stdin is a terminal, it prompts interactively (no echo).
// If stdin is a pipe, it reads the first line.
func readPasswordFromStdin() (string, error) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		fmt.Fprintln(os.Stderr, "Tip: save password to .booth/.booth.password (git ignored) or pipe via stdin to skip this prompt.")
		fmt.Fprintln(os.Stderr, "Username: coder")
		fmt.Fprint(os.Stderr, "Password: ")
		password, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr) // newline after hidden input
		if err != nil {
			return "", fmt.Errorf("failed to read password: %w", err)
		}
		return string(password), nil
	}

	// Piped input: read first line
	scanner := bufio.NewScanner(os.Stdin)
	if scanner.Scan() {
		return scanner.Text(), nil
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", fmt.Errorf("no input received on stdin")
}

// validatePasswordFile checks that the password file has safe permissions and is gitignored.
func validatePasswordFile(passwordFile, codeDir string) error {
	// Check file permissions (skip on Windows)
	if runtime.GOOS != "windows" {
		info, err := os.Stat(passwordFile)
		if err != nil {
			return fmt.Errorf("cannot stat password file %q: %w", passwordFile, err)
		}
		if info.Mode().Perm()&0077 != 0 {
			return fmt.Errorf(
				"password file %q has too-permissive permissions %04o; "+
					"group and others must have no access. Fix with: chmod 600 %s",
				passwordFile, info.Mode().Perm(), passwordFile,
			)
		}
	}

	// Check gitignore
	if err := checkPasswordFileGitignored(passwordFile, codeDir); err != nil {
		return err
	}

	return nil
}

// checkPasswordFileGitignored verifies that .booth/.booth.password is gitignored.
// Skips the check if git is not available or the project is not a git repo.
func checkPasswordFileGitignored(passwordFile, codeDir string) error {
	gitPath, err := exec.LookPath("git")
	if err != nil {
		// git not installed, skip check
		return nil
	}

	// Check if we are in a git repo
	cmd := exec.Command(gitPath, "-C", codeDir, "rev-parse", "--git-dir")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		// Not a git repo, skip check
		return nil
	}

	// git check-ignore returns exit 0 if ignored, exit 1 if NOT ignored
	cmd = exec.Command(gitPath, "-C", codeDir, "check-ignore", "-q", ".booth/.booth.password")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return fmt.Errorf(
			"password file %q is NOT gitignored. "+
				"Add '.booth.password' to .booth/.gitignore before using this feature. "+
				"Refusing to run to prevent accidental credential exposure",
			passwordFile,
		)
	}

	return nil
}
