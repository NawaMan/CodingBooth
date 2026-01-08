package workspace

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

// ShowDebugBanner prints debug information if verbose mode is enabled.
func ShowDebugBanner(ctx appctx.AppContext) appctx.AppContext {
	if !ctx.Verbose() {
		return ctx
	}

	fmt.Println()
	fmt.Printf("SCRIPT_NAME:    %s\n", ctx.ScriptName())
	fmt.Printf("SCRIPT_DIR:     %s\n", ctx.ScriptDir())
	fmt.Printf("WS_VERSION:     %s\n", ctx.WsVersion())
	fmt.Printf("CONFIG_FILE:    %s\n", ctx.ConfigFile())
	fmt.Println()
	fmt.Printf("CONTAINER_NAME: %s\n", ctx.Name())
	fmt.Printf("DAEMON:         %t\n", ctx.Daemon())
	fmt.Printf("DOCKER_FILE:    %s\n", ctx.Dockerfile())
	fmt.Printf("DRYRUN:         %t\n", ctx.Dryrun())
	fmt.Printf("KEEPALIVE:      %t\n", ctx.KeepAlive())
	fmt.Println()
	fmt.Printf("IMAGE_NAME:     %s\n", ctx.Image())
	fmt.Printf("IMAGE_MODE:     %s\n", ctx.ImageMode())
	fmt.Printf("LOCAL_BUILD:    %t\n", ctx.LocalBuild())
	fmt.Printf("VARIANT:        %s\n", ctx.Variant())
	fmt.Printf("VERSION:        %s\n", ctx.Version())
	fmt.Printf("PREBUILD_REPO:  %s\n", ctx.PrebuildRepo())
	fmt.Printf("DO_PULL:        %t\n", ctx.Pull())
	fmt.Println()
	fmt.Printf("HOST_UID:       %s\n", ctx.HostUID())
	fmt.Printf("HOST_GID:       %s\n", ctx.HostGID())
	fmt.Printf("WORKSPACE_PATH: %s\n", ctx.Workspace())
	fmt.Printf("WORKSPACE_PORT: %d\n", 10000)
	fmt.Printf("HOST_PORT:      %d\n", ctx.PortNumber())
	fmt.Printf("PORT_GENERATED: %t\n", ctx.PortGenerated())
	fmt.Println()
	fmt.Printf("DIND:           %t\n", ctx.Dind())
	fmt.Println()
	fmt.Printf("CONTAINER_ENV_FILE: %s\n", ctx.EnvFile())
	fmt.Println()
	fmt.Printf("BUILD_ARGS: %s\n", listOfArgsToString(ctx.BuildArgs()))
	fmt.Printf("RUN_ARGS:   %s\n", listOfArgsToString(ctx.RunArgs()))
	fmt.Printf("CMDS:       %s\n", listOfArgsToString(ctx.Cmds()))
	fmt.Println()

	// Warning if BUILD_ARGS provided but no build is being performed
	if ctx.BuildArgs().Length() > 0 && !ctx.LocalBuild() {
		fmt.Fprintln(os.Stderr, "⚠️  Warning: BUILD_ARGS provided, but no build is being performed (using prebuilt image).")
		fmt.Println()
	}

	return ctx
}

// listOfArgsToString converts a list of arguments to a string representation.
func listOfArgsToString(list ilist.List[ilist.List[string]]) string {
	if list.Length() == 0 {
		return ""
	}

	var result strings.Builder
	for _, args := range list.Slice() {
		result.WriteString(argsToString(args.Slice()))
	}

	return result.String()
}

// argsToString converts a slice of arguments to a string representation.
func argsToString(args []string) string {
	if len(args) == 0 {
		return ""
	}

	var result strings.Builder
	for _, arg := range args {
		// Quote arguments that contain spaces or special characters
		if strings.ContainsAny(arg, " \t\n\"'") {
			result.WriteString(fmt.Sprintf(" \"%s\"", strings.ReplaceAll(arg, "\"", "\\\"")))
		} else {
			result.WriteString(fmt.Sprintf(" \"%s\"", arg))
		}
	}

	return result.String()
}
