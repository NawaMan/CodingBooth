// Package appctx provides centralized application context for workspace configuration and state.
//
// AppContext is an immutable snapshot (like List), AppContextBuilder is mutable (like AppendableList).
// Use ToBuilder() and Build() to convert between them.
package appctx

import (
	"fmt"
	"strings"

	"github.com/nawaman/workspace/src/pkg/ilist"
)

// AppContext is an immutable snapshot of workspace configuration and state.
type AppContext struct {
	values AppContextBuilder

	dryrun     bool
	verbose    bool
	configFile string
	workspace  string
	version    string

	commonArgs ilist.List[ilist.List[string]]
	buildArgs  ilist.List[ilist.List[string]]
	runArgs    ilist.List[ilist.List[string]]
	cmds       ilist.List[ilist.List[string]]
}

// NewAppContext creates a new immutable AppContext with defaults matching workspace initialization.
func NewAppContext(builder *AppContextBuilder) AppContext {
	return AppContext{
		values:     *builder.Clone(),
		dryrun:     builder.Config.Dryrun.ValueOr(false),
		verbose:    builder.Config.Verbose.ValueOr(false),
		configFile: builder.Config.Config.ValueOr(""),
		workspace:  builder.Config.Workspace.ValueOr(""),
		version:    builder.Config.Version.ValueOr(builder.Version),
		commonArgs: builder.CommonArgs.ToList(),
		buildArgs:  builder.BuildArgs.ToList(),
		runArgs:    builder.RunArgs.ToList(),
		cmds:       builder.Cmds.ToList(),
	}
}

//== AppContext ==

// constant
func (ctx AppContext) PrebuildRepo() string { return ctx.values.PrebuildRepo }
func (ctx AppContext) WsVersion() string    { return ctx.values.WsVersion }
func (ctx AppContext) SetupsDir() string    { return ctx.values.SetupsDir }

// bootstrap flags
func (ctx AppContext) Dryrun() bool       { return ctx.dryrun }
func (ctx AppContext) Verbose() bool      { return ctx.verbose }
func (ctx AppContext) ConfigFile() string { return ctx.configFile }
func (ctx AppContext) Workspace() string  { return ctx.workspace }
func (ctx AppContext) Version() string    { return ctx.version }

// taken from the script runtime
func (ctx AppContext) ScriptName() string { return ctx.values.ScriptName }
func (ctx AppContext) ScriptDir() string  { return ctx.values.ScriptDir }
func (ctx AppContext) LibDir() string     { return ctx.values.LibDir }

// derived from variant
func (ctx AppContext) HasNotebook() bool { return ctx.values.HasNotebook }
func (ctx AppContext) HasVscode() bool   { return ctx.values.HasVscode }
func (ctx AppContext) HasDesktop() bool  { return ctx.values.HasDesktop }

// derived from DinD
func (ctx AppContext) CreatedDindNet() bool { return ctx.values.CreatedDindNet }

// derived from image determination of image
func (ctx AppContext) RunMode() string   { return ctx.values.RunMode }
func (ctx AppContext) LocalBuild() bool  { return ctx.values.LocalBuild }
func (ctx AppContext) ImageMode() string { return ctx.values.ImageMode }

// derived from port determination
func (ctx AppContext) PortGenerated() bool { return ctx.values.PortGenerated }
func (ctx AppContext) PortNumber() int     { return ctx.values.PortNumber }

// Flags
func (ctx AppContext) KeepAlive() bool    { return ctx.values.Config.KeepAlive }
func (ctx AppContext) SilenceBuild() bool { return ctx.values.Config.SilenceBuild }
func (ctx AppContext) Daemon() bool       { return ctx.values.Config.Daemon }
func (ctx AppContext) Pull() bool         { return ctx.values.Config.Pull }
func (ctx AppContext) Dind() bool         { return ctx.values.Config.Dind }

// Image Configuration
func (ctx AppContext) Dockerfile() string { return ctx.values.Config.Dockerfile }
func (ctx AppContext) Image() string      { return ctx.values.Config.Image }
func (ctx AppContext) Variant() string    { return ctx.values.Config.Variant }

// Runtime values
func (ctx AppContext) ProjectName() string { return ctx.values.Config.ProjectName }
func (ctx AppContext) HostUID() string     { return ctx.values.Config.HostUID }
func (ctx AppContext) HostGID() string     { return ctx.values.Config.HostGID }
func (ctx AppContext) Timezone() string    { return ctx.values.Config.Timezone }

// Container Configuration
func (ctx AppContext) Name() string    { return ctx.values.Config.Name }
func (ctx AppContext) Port() string    { return ctx.values.Config.Port }
func (ctx AppContext) EnvFile() string { return ctx.values.Config.EnvFile }

// derived from all the context processing (IMMUTABLE SNAPSHOTS)
func (ctx AppContext) CommonArgs() ilist.List[ilist.List[string]] { return ctx.commonArgs }
func (ctx AppContext) BuildArgs() ilist.List[ilist.List[string]]  { return ctx.buildArgs }
func (ctx AppContext) RunArgs() ilist.List[ilist.List[string]]    { return ctx.runArgs }
func (ctx AppContext) Cmds() ilist.List[ilist.List[string]]       { return ctx.cmds }

// ToBuilder converts an immutable AppContext back into a mutable builder.
func (ctx AppContext) ToBuilder() *AppContextBuilder {
	b := ctx.values.Clone()

	b.CommonArgs = ctx.commonArgs.ToBuilder()
	b.BuildArgs = ctx.buildArgs.ToBuilder()
	b.RunArgs = ctx.runArgs.ToBuilder()
	b.Cmds = ctx.cmds.ToBuilder()

	return b
}

// String returns a string representation of the app context.
func (ctx AppContext) String() string {
	var str strings.Builder

	str.WriteString("==| AppContext |==================================================\n")

	fmt.Fprintf(&str, "# Constants ---------------------\n")
	fmt.Fprintf(&str, "    PrebuildRepo:     %q\n", ctx.PrebuildRepo())
	fmt.Fprintf(&str, "    WsVersion:        %q\n", ctx.WsVersion())
	fmt.Fprintf(&str, "    SetupsDir:        %q\n", ctx.SetupsDir())

	fmt.Fprintf(&str, "# Script Runtime ----------------\n")
	fmt.Fprintf(&str, "    ScriptName:       %q\n", ctx.ScriptName())
	fmt.Fprintf(&str, "    ScriptDir:        %q\n", ctx.ScriptDir())
	fmt.Fprintf(&str, "    LibDir:           %q\n", ctx.LibDir())

	fmt.Fprintf(&str, "# Variant -----------------------\n")
	fmt.Fprintf(&str, "    HasNotebook:      %t\n", ctx.HasNotebook())
	fmt.Fprintf(&str, "    HasVscode:        %t\n", ctx.HasVscode())
	fmt.Fprintf(&str, "    HasDesktop:       %t\n", ctx.HasDesktop())

	fmt.Fprintf(&str, "# DinD --------------------------\n")
	fmt.Fprintf(&str, "    CreatedDindNet:   %t\n", ctx.CreatedDindNet())

	fmt.Fprintf(&str, "# Image -------------------------\n")
	fmt.Fprintf(&str, "    RunMode:          %q\n", ctx.RunMode())
	fmt.Fprintf(&str, "    LocalBuild:       %t\n", ctx.LocalBuild())
	fmt.Fprintf(&str, "    ImageMode:        %q\n", ctx.ImageMode())

	fmt.Fprintf(&str, "# Port --------------------------\n")
	fmt.Fprintf(&str, "    PortGenerated:    %t\n", ctx.PortGenerated())
	fmt.Fprintf(&str, "    PortNumber:       %d\n", ctx.PortNumber())

	fmt.Fprintf(&str, "# General configuration ---------\n")
	fmt.Fprintf(&str, "    Dryrun:           %t\n", ctx.Dryrun())
	fmt.Fprintf(&str, "    Verbose:          %t\n", ctx.Verbose())
	fmt.Fprintf(&str, "    ConfigFile:       %q\n", ctx.ConfigFile())
	fmt.Fprintf(&str, "    Workspace:        %q\n", ctx.Workspace())
	fmt.Fprintf(&str, "    Version:          %q\n", ctx.Version())

	fmt.Fprintf(&str, "# Flags -------------------------\n")
	fmt.Fprintf(&str, "    KeepAlive:        %t\n", ctx.KeepAlive())
	fmt.Fprintf(&str, "    SilenceBuild:     %t\n", ctx.SilenceBuild())
	fmt.Fprintf(&str, "    Daemon:           %t\n", ctx.Daemon())
	fmt.Fprintf(&str, "    Pull:             %t\n", ctx.Pull())
	fmt.Fprintf(&str, "    Dind:             %t\n", ctx.Dind())

	fmt.Fprintf(&str, "# Image Configuration -----------\n")
	fmt.Fprintf(&str, "    Dockerfile:       %q\n", ctx.Dockerfile())
	fmt.Fprintf(&str, "    Image:            %q\n", ctx.Image())
	fmt.Fprintf(&str, "    Variant:          %q\n", ctx.Variant())

	fmt.Fprintf(&str, "# Runtime values ----------------\n")
	fmt.Fprintf(&str, "    ProjectName:      %q\n", ctx.ProjectName())
	fmt.Fprintf(&str, "    HostUID:          %q\n", ctx.HostUID())
	fmt.Fprintf(&str, "    HostGID:          %q\n", ctx.HostGID())
	fmt.Fprintf(&str, "    Timezone:         %q\n", ctx.Timezone())

	fmt.Fprintf(&str, "# Container Configuration -------\n")
	fmt.Fprintf(&str, "    Name:             %q\n", ctx.Name())
	fmt.Fprintf(&str, "    Port:             %q\n", ctx.Port())
	fmt.Fprintf(&str, "    EnvFile:          %q\n", ctx.EnvFile())

	fmt.Fprintf(&str, "# Lists (Immutable) -------------\n")
	formatList(&str, "CommonArgs", ctx.CommonArgs(), "    ")
	formatList(&str, "BuildArgs", ctx.BuildArgs(), "    ")
	formatList(&str, "RunArgs", ctx.RunArgs(), "    ")
	formatList(&str, "Cmds", ctx.Cmds(), "    ")

	str.WriteString("==================================================================\n")

	return str.String()
}

func formatList[TYPE any](str *strings.Builder, name string, list ilist.List[TYPE], indent string) {
	str.WriteString(indent)
	str.WriteString(name)
	str.WriteString(": [\n")

	list.Range(func(_ int, v TYPE) bool {
		fmt.Fprintf(str, "%s  %v\n", indent, v)
		return true
	})

	str.WriteString(indent)
	str.WriteString("]\n")
}
