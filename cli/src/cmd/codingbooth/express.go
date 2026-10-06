// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
)

// expressPlan is one `booth express` invocation, split into the spec the
// compiler writes and the launch flags booth run still has to see.
type expressPlan struct {
	code       string
	name       string
	daemon     bool
	keepAlive  bool
	image      bool
	dockerfile bool
	boothfile  bool
	flags      initFlags
	launch     []string
}

// expressRefused are flags that would read or write the project .booth, or
// that only make sense while configuring one. Express errors as soon as it
// sees the flag, even when the value is missing.
var expressRefused = map[string]string{
	"--config":            "express does not read a project config; pass the settings as flags",
	"--profile":           "express ignores profiles",
	"--add-select":        "express has no existing selection to add to; pass --select",
	"--remove-select":     "express has no existing selection to remove from",
	"--add-expose":        "express has no existing ports to add to; pass --expose",
	"--remove-expose":     "express has no existing ports to remove",
	"--add-env":           "express has no existing env to add to; pass --env",
	"--remove-env":        "express has no existing env to remove",
	"--add-mount":         "express has no existing mounts to add to; pass --mount",
	"--remove-mount":      "express has no existing mounts to remove",
	"--overwrite":         "express does not edit a project .booth",
	"--beside":            "express does not edit a project .booth",
	"--no-tui":            "express does not open booth config",
	"--web":               "express does not open booth config",
	"--start":             "express does not open booth config",
	"--full":              "express does not open booth config",
	"--detail":            "express does not open booth config",
	"--debug":             "express does not open booth config",
	"--writable-booth":    "express mounts its own spec read-only",
	"--no-writable-booth": "express mounts its own spec read-only",
	"--console-spec":      "express does not take a project console spec",
	"--leave-tmp-on-exit": "express does not use the project's .booth/.tmp",
	"--keep-tmp-on-start": "express does not use the project's .booth/.tmp",
	"--booth-dir":         "express chooses its own spec directory",
}

// expressSetDenied are config keys run would honor from a file, but that
// point at the project .booth (cache, shared, tmp, console). The matching
// flags are refused too, so the flag and the key stay aligned.
var expressSetDenied = map[string]bool{
	"cache-files":       true,
	"cache-dirs":        true,
	"shared-files":      true,
	"shared-dirs":       true,
	"writable-booth":    true,
	"console-spec":      true,
	"leave-tmp-on-exit": true,
	"keep-tmp-on-start": true,
}

func runExpress(version string) {
	args := os.Args[2:]
	if len(args) > 0 && (args[0] == "help" || args[0] == "--help" || args[0] == "-h") {
		showHelpExpress()
		return
	}
	plan, err := parseExpressArgs(args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if plan.code == "" {
		cwd, cwdErr := os.Getwd()
		if cwdErr != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", cwdErr)
			os.Exit(1)
		}
		abs, absErr := filepath.Abs(cwd)
		if absErr != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", absErr)
			os.Exit(1)
		}
		plan.code = abs
	}

	persist := expressPersists(plan)
	specRoot, err := expressSpecRoot(plan.code, plan.name, persist)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	// PrepareBoothTmp refuses to create a missing .booth, and the mount is
	// what hides a project .booth inside the container. Always create one,
	// even when nothing is compiled.
	if err := os.MkdirAll(filepath.Join(specRoot, ".booth"), 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	wroteConfig, wroteBoothfile, err := compileExpressSpec(plan, specRoot, version)
	if err != nil {
		if !persist {
			_ = os.RemoveAll(specRoot)
		}
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	boothDir := filepath.Join(specRoot, ".booth")
	argv := []string{os.Args[0], "--code", plan.code, "--booth-dir", boothDir}
	if wroteConfig {
		argv = append(argv, "--config", filepath.Join(boothDir, "config.toml"))
	}
	if wroteBoothfile {
		argv = append(argv, "--boothfile", filepath.Join(boothDir, "Boothfile"))
	}
	argv = append(argv, plan.launch...)
	runBooth(version, argv)
}

// expressPersists reports whether the spec has to outlive this process.
// A daemon or keep-alive container is started again later and re-reads the
// mounted spec. CB_DAEMON and CB_KEEP_ALIVE count, because those env vars
// still apply and the flags only override them when present.
func expressPersists(plan expressPlan) bool {
	if plan.daemon || plan.keepAlive {
		return true
	}
	return envBool("CB_DAEMON") || envBool("CB_KEEP_ALIVE")
}

func envBool(key string) bool {
	value, ok := os.LookupEnv(key)
	if !ok {
		return false
	}
	parsed, err := strconv.ParseBool(value)
	return err == nil && parsed
}

// expressSpecRoot is the directory whose .booth/ express mounts. A foreground
// run uses a temp dir. A persisted run uses a cache dir keyed by the code
// path and the raw --name (which may still contain {port}).
func expressSpecRoot(code, name string, persist bool) (string, error) {
	if !persist {
		return os.MkdirTemp("", "codingbooth-express-")
	}
	cacheRoot, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	return expressCacheDir(cacheRoot, code, name)
}

// expressCacheDir is <cacheRoot>/codingbooth/express/<hash>. The hash is the
// first 8 bytes of sha256(code + "\n" + name), hex-encoded. name defaults to
// the code folder's base name. The same code and name reuse one directory.
func expressCacheDir(cacheRoot, code, name string) (string, error) {
	if name == "" {
		name = filepath.Base(code)
	}
	sum := sha256.Sum256([]byte(code + "\n" + name))
	id := hex.EncodeToString(sum[:8])
	dir := filepath.Join(cacheRoot, "codingbooth", "express", id)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	return dir, nil
}

// removeExpressTempSpec deletes a foreground express spec. boothDir is the
// .booth directory; its parent is the temp dir MkdirTemp created. Anything
// else — a cache spec, or a --booth-dir a caller chose — is left in place.
func removeExpressTempSpec(boothDir string) {
	if !expressTempSpec(boothDir) {
		return
	}
	_ = os.RemoveAll(filepath.Dir(boothDir))
}

func expressTempSpec(boothDir string) bool {
	if boothDir == "" {
		return false
	}
	specRoot := filepath.Dir(boothDir)
	if !strings.HasPrefix(filepath.Base(specRoot), "codingbooth-express-") {
		return false
	}
	// A direct child of the temp dir only. A folder that merely contains the
	// prefix somewhere under /tmp is not one express created.
	rel, err := filepath.Rel(os.TempDir(), specRoot)
	if err != nil || rel == "." || strings.Contains(rel, string(filepath.Separator)) || strings.HasPrefix(rel, "..") {
		return false
	}
	return true
}

func parseExpressArgs(args []string) (expressPlan, error) {
	var plan expressPlan
	for index := 0; index < len(args); index++ {
		arg := args[index]
		if arg == "--" {
			plan.launch = append(plan.launch, args[index:]...)
			break
		}
		if reason, refused := expressRefused[arg]; refused {
			return expressPlan{}, fmt.Errorf("%s: %s", arg, reason)
		}

		switch arg {
		case "--select", "--cmd", "--expose", "--env", "--mount", "--set", "--templates-path", "--apt-snapshot":
			value, err := expressValue(args, index, arg)
			if err != nil {
				return expressPlan{}, err
			}
			if err := expressTakeSpec(arg, value, &plan.flags); err != nil {
				return expressPlan{}, err
			}
			index++
			continue

		case "--code", "--name", "--variant", "--port", "--image", "--dockerfile", "--boothfile":
			value, err := expressValue(args, index, arg)
			if err != nil {
				return expressPlan{}, err
			}
			if err := expressTakeRecorded(arg, value, &plan); err != nil {
				return expressPlan{}, err
			}
			// --code is added once by runExpress. The others stay on the
			// launch line so they override the generated file.
			if arg != "--code" {
				plan.launch = append(plan.launch, arg, value)
			}
			index++
			continue

		case "--daemon":
			plan.daemon = true
		case "--keep-alive":
			plan.keepAlive = true
		}
		// Unknown tokens, including a docker flag and its following value,
		// are forwarded one at a time. Express does not consume the next
		// argument of a flag it does not know.
		plan.launch = append(plan.launch, arg)
	}

	if len(plan.flags.selectDSLs) > 0 && (plan.image || plan.dockerfile || plan.boothfile) {
		return expressPlan{}, fmt.Errorf("--select cannot be combined with --image, --dockerfile, or --boothfile")
	}
	if len(plan.flags.selectDSLs) == 0 && (plan.flags.templatesPath != "" || plan.flags.aptSnapshotSet) {
		return expressPlan{}, fmt.Errorf("--templates-path and --apt-snapshot require --select")
	}
	if err := rejectExpressSets(plan.flags.sets); err != nil {
		return expressPlan{}, err
	}
	return plan, nil
}

func expressValue(args []string, index int, flag string) (string, error) {
	if index+1 >= len(args) || args[index+1] == "" || strings.HasPrefix(args[index+1], "--") {
		return "", fmt.Errorf("%s requires a value", flag)
	}
	return args[index+1], nil
}

func expressTakeSpec(flag, value string, flags *initFlags) error {
	switch flag {
	case "--select":
		flags.selectDSLs = append(flags.selectDSLs, value)
	case "--cmd":
		flags.cmds = append(flags.cmds, shellSplit(value)...)
	case "--expose":
		if err := validateExpose(value); err != nil {
			return err
		}
		flags.exposes = append(flags.exposes, value)
	case "--env":
		if err := validateEnv(value); err != nil {
			return err
		}
		flags.envs = append(flags.envs, value)
	case "--mount":
		if err := validateMount(value); err != nil {
			return err
		}
		flags.mounts = append(flags.mounts, value)
	case "--set":
		flags.sets = append(flags.sets, value)
	case "--templates-path":
		flags.templatesPath = value
	case "--apt-snapshot":
		id, err := parseAptSnapshotFlag(value)
		if err != nil {
			return err
		}
		flags.aptSnapshot = id
		flags.aptSnapshotSet = true
	}
	return nil
}

func expressTakeRecorded(flag, value string, plan *expressPlan) error {
	switch flag {
	case "--code":
		abs, err := filepath.Abs(value)
		if err != nil {
			return err
		}
		plan.code = abs
	case "--name":
		plan.name = value
	case "--variant":
		plan.flags.variant = value
	case "--port":
		plan.flags.port = value
	case "--image":
		plan.image = true
	case "--dockerfile":
		plan.dockerfile = true
	case "--boothfile":
		plan.boothfile = true
	}
	return nil
}

// rejectExpressSets refuses keys that would look effective in the generated
// file and then be ignored, or that point at the project .booth. Unknown
// keys fail the same way `booth config --set` fails.
func rejectExpressSets(sets []string) error {
	schema := appctx.ConfigKeys()
	for _, set := range sets {
		key, _, _ := strings.Cut(set, "=")
		if expressSetDenied[key] {
			return fmt.Errorf("--set %s is not available to express", key)
		}
		spec, known := schema[key]
		if known && !spec.Read {
			return fmt.Errorf("--set %s is not read from config.toml; pass it as a flag", key)
		}
		if _, err := parseSetOverrides([]string{set}); err != nil {
			return err
		}
	}
	return nil
}

// compileExpressSpec writes the generated spec under specRoot. projectRoot is
// specRoot, so a .booth/templates or .booth/recipes in the user's code is
// not merged. With no --select and no file-backed spec flags, nothing is
// written: an empty Boothfile would make run build an empty image instead
// of starting the prebuilt variant.
func compileExpressSpec(plan expressPlan, specRoot, version string) (bool, bool, error) {
	needsFile := len(plan.flags.selectDSLs) > 0 ||
		len(plan.flags.exposes) > 0 ||
		len(plan.flags.envs) > 0 ||
		len(plan.flags.mounts) > 0 ||
		len(plan.flags.cmds) > 0 ||
		len(plan.flags.sets) > 0
	if !needsFile {
		return false, false, nil
	}

	flags := plan.flags
	var out *output.BoothOutput
	var err error
	if len(flags.selectDSLs) > 0 {
		if flags.templatesPath == "" {
			flags.templatesPath = os.Getenv("CB_TEMPLATES_PATH")
		}
		templatesPath, cleanup := resolveTemplatesPath(flags, version)
		defer cleanup()
		flags.templatesPath = templatesPath
		out, _, err = compileSelectionE(flags, specRoot, nil)
	} else {
		out, _, err = compileEmptyE(flags)
		if out != nil {
			// compileEmptyE always allocates a Boothfile. Passing that empty
			// file to run builds an image with no setups.
			out.Boothfile = nil
		}
	}
	if err != nil {
		return false, false, err
	}
	if out.Boothfile != nil && out.Boothfile.Content != "" {
		applyBoothAptSnapshot(out, specRoot, flags)
	}
	out.Command = expressHeaderCommand(plan)
	if err := output.WriteOutput(out, specRoot); err != nil {
		return false, false, err
	}

	boothDir := filepath.Join(specRoot, ".booth")
	_, configErr := os.Stat(filepath.Join(boothDir, "config.toml"))
	_, boothfileErr := os.Stat(filepath.Join(boothDir, "Boothfile"))
	return configErr == nil, boothfileErr == nil, nil
}

func expressHeaderCommand(plan expressPlan) string {
	parts := []string{"booth express"}
	for _, dsl := range plan.flags.selectDSLs {
		parts = append(parts, "--select "+dsl)
	}
	if plan.flags.variant != "" {
		parts = append(parts, "--variant "+plan.flags.variant)
	}
	if plan.flags.port != "" {
		parts = append(parts, "--port "+plan.flags.port)
	}
	return strings.Join(parts, " ")
}
