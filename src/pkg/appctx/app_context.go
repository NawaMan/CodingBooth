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

type AppConfig struct {

	// --------------------
	// General configuration
	// --------------------
	ConfigFile    string `toml:"ConfigFile,omitempty"    envconfig:"CONFIG_FILE" default:"./ws--config.toml"`
	WorkspacePath string `toml:"WorkspacePath,omitempty" envconfig:"WORKSPACE_PATH"`

	// --------------------
	// Flags
	// --------------------
	Dryrun       bool `toml:"Dryrun,omitempty"       envconfig:"DRYRUN" default:"false"`
	Verbose      bool `toml:"Verbose,omitempty"      envconfig:"VERBOSE" default:"false"`
	Keepalive    bool `toml:"Keepalive,omitempty"    envconfig:"KEEPALIVE" default:"false"`
	SilenceBuild bool `toml:"SilenceBuild,omitempty" envconfig:"SILENCE_BUILD" default:"false"`
	Daemon       bool `toml:"Daemon,omitempty"       envconfig:"DAEMON" default:"false"`
	DoPull       bool `toml:"DoPull,omitempty"       envconfig:"DO_PULL" default:"false"`
	Dind         bool `toml:"Dind,omitempty"         envconfig:"DIND" default:"false"`

	// --------------------
	// Image configuration
	// --------------------
	DockerFile string `toml:"DockerFile,omitempty"   envconfig:"DOCKER_FILE"`
	ImageName  string `toml:"ImageName,omitempty"    envconfig:"IMAGE_NAME"`
	Variant    string `toml:"Variant,omitempty"      envconfig:"VARIANT" default:"default"`
	Version    string `toml:"Version,omitempty"      envconfig:"VERSION" default:"latest"`

	// --------------------
	// Runtime values
	// --------------------
	ProjectName string `toml:"ProjectName,omitempty" envconfig:"PROJECT_NAME"`
	HostUID     string `toml:"HostUID,omitempty"     envconfig:"HOST_UID"`
	HostGID     string `toml:"HostGID,omitempty"     envconfig:"HOST_GID"`
	Timezone    string `toml:"Timezone,omitempty"    envconfig:"TIMEZONE"`

	// --------------------
	// Container configuration
	// --------------------
	ContainerName    string `toml:"ContainerName,omitempty"    envconfig:"CONTAINER_NAME"`
	WorkspacePort    string `toml:"WorkspacePort,omitempty"    envconfig:"WORKSPACE_PORT" default:"NEXT"`
	HostPort         string `toml:"HostPort,omitempty"         envconfig:"HOST_PORT"`
	ContainerEnvFile string `toml:"ContainerEnvFile,omitempty" envconfig:"CONTAINER_ENV_FILE"`

	// --------------------
	// Docker-in-Docker
	// --------------------
	DindNet   string `toml:"DindNet,omitempty"    envconfig:"DIND_NET"`
	DindName  string `toml:"DindName,omitempty"   envconfig:"DIND_NAME"`
	DockerBin string `toml:"DockerBin,omitempty"  envconfig:"DOCKER_BIN"`

	// --------------------
	// TOML-friendly array fields
	// --------------------
	CommonArgsSlice []string `toml:"CommonArgs,omitempty"`
	BuildArgsSlice  []string `toml:"BuildArgs,omitempty"`
	RunArgsSlice    []string `toml:"RunArgs,omitempty"`
	CmdsSlice       []string `toml:"Cmds,omitempty"`
}

// AppContextBuilder is a mutable builder for constructing AppContext instances.
type AppContextBuilder struct {

	// constant
	PrebuildRepo string
	WsVersion    string
	SetupsDir    string

	// taken from the script runtime
	ScriptName string
	ScriptDir  string
	LibDir     string

	// derived from variant
	HasNotebook bool
	HasVscode   bool
	HasDesktop  bool

	// derived from DinD
	CreatedDindNet bool

	// derived from image determination of image
	RunMode    string
	LocalBuild bool
	ImageMode  string

	// derived from all the context processing
	CommonArgs    *ilist.AppendableList[string]
	BuildArgs     *ilist.AppendableList[string]
	RunArgs       *ilist.AppendableList[string]
	Cmds          *ilist.AppendableList[string]
	KeepaliveArgs *ilist.AppendableList[string]
	TtyArgs       *ilist.AppendableList[string]

	// derived from port determination
	PortGenerated bool

	// Configurable
	Config AppConfig
}

// AppContext is an immutable snapshot of workspace configuration and state.
type AppContext struct {
	values AppContextBuilder

	commonArgs    ilist.List[string]
	buildArgs     ilist.List[string]
	runArgs       ilist.List[string]
	cmds          ilist.List[string]
	keepaliveArgs ilist.List[string]
	ttyArgs       ilist.List[string]
}

// NewAppContext creates a new immutable AppContext with defaults matching workspace.sh initialization.
func NewAppContext(builder *AppContextBuilder) AppContext {
	return AppContext{
		values:        *cloneAppContextBuilder(builder),
		commonArgs:    cloneAppendableListToList(builder.CommonArgs),
		buildArgs:     cloneAppendableListToList(builder.BuildArgs),
		runArgs:       cloneAppendableListToList(builder.RunArgs),
		cmds:          cloneAppendableListToList(builder.Cmds),
		keepaliveArgs: cloneAppendableListToList(builder.KeepaliveArgs),
		ttyArgs:       cloneAppendableListToList(builder.TtyArgs),
	}
}

// Clone the content of the app config.
func cloneAppConfig(config *AppConfig) *AppConfig {
	copy := *config

	copy.CommonArgsSlice = append([]string(nil), config.CommonArgsSlice...)
	copy.BuildArgsSlice = append([]string(nil), config.BuildArgsSlice...)
	copy.RunArgsSlice = append([]string(nil), config.RunArgsSlice...)
	copy.CmdsSlice = append([]string(nil), config.CmdsSlice...)

	return &copy
}

// Clone the content of the app context builder.
func cloneAppContextBuilder(builder *AppContextBuilder) *AppContextBuilder {
	copy := *builder

	copy.CommonArgs = cloneAppendableList(builder.CommonArgs)
	copy.BuildArgs = cloneAppendableList(builder.BuildArgs)
	copy.RunArgs = cloneAppendableList(builder.RunArgs)
	copy.Cmds = cloneAppendableList(builder.Cmds)
	copy.KeepaliveArgs = cloneAppendableList(builder.KeepaliveArgs)
	copy.TtyArgs = cloneAppendableList(builder.TtyArgs)

	copy.Config = *cloneAppConfig(&builder.Config)

	return &copy
}

// Clone the content of the appendable list.
func cloneAppendableList(list *ilist.AppendableList[string]) *ilist.AppendableList[string] {
	if list == nil {
		return ilist.NewAppendableList[string]()
	}
	return list.Clone()
}

// Clone the content of the appendable list.
func cloneAppendableListToList(list *ilist.AppendableList[string]) ilist.List[string] {
	if list == nil {
		return ilist.NewList[string]()
	}
	return list.Snapshot()
}

//== AppContextBuilder ==

// Build creates an immutable AppContext snapshot from this builder.
func (b *AppContextBuilder) Build() AppContext {
	return NewAppContext(b)
}

//== AppContext ==

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

// constant
func (ctx AppContext) PrebuildRepo() string { return ctx.values.PrebuildRepo }
func (ctx AppContext) WsVersion() string    { return ctx.values.WsVersion }
func (ctx AppContext) SetupsDir() string    { return ctx.values.SetupsDir }

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

// Configurable - General configuration
func (ctx AppContext) ConfigFile() string    { return ctx.values.Config.ConfigFile }
func (ctx AppContext) WorkspacePath() string { return ctx.values.Config.WorkspacePath }

// Flags
func (ctx AppContext) Dryrun() bool       { return ctx.values.Config.Dryrun }
func (ctx AppContext) Verbose() bool      { return ctx.values.Config.Verbose }
func (ctx AppContext) Keepalive() bool    { return ctx.values.Config.Keepalive }
func (ctx AppContext) SilenceBuild() bool { return ctx.values.Config.SilenceBuild }
func (ctx AppContext) Daemon() bool       { return ctx.values.Config.Daemon }
func (ctx AppContext) DoPull() bool       { return ctx.values.Config.DoPull }
func (ctx AppContext) Dind() bool         { return ctx.values.Config.Dind }

// Image Configuration
func (ctx AppContext) DockerFile() string { return ctx.values.Config.DockerFile }
func (ctx AppContext) ImageName() string  { return ctx.values.Config.ImageName }
func (ctx AppContext) Variant() string    { return ctx.values.Config.Variant }
func (ctx AppContext) Version() string    { return ctx.values.Config.Version }

// Runtime values
func (ctx AppContext) ProjectName() string { return ctx.values.Config.ProjectName }
func (ctx AppContext) HostUID() string     { return ctx.values.Config.HostUID }
func (ctx AppContext) HostGID() string     { return ctx.values.Config.HostGID }
func (ctx AppContext) Timezone() string    { return ctx.values.Config.Timezone }

// Container Configuration
func (ctx AppContext) ContainerName() string    { return ctx.values.Config.ContainerName }
func (ctx AppContext) WorkspacePort() string    { return ctx.values.Config.WorkspacePort }
func (ctx AppContext) HostPort() string         { return ctx.values.Config.HostPort }
func (ctx AppContext) ContainerEnvFile() string { return ctx.values.Config.ContainerEnvFile }

// Docker-in-Docker
func (ctx AppContext) DindNet() string   { return ctx.values.Config.DindNet }
func (ctx AppContext) DindName() string  { return ctx.values.Config.DindName }
func (ctx AppContext) DockerBin() string { return ctx.values.Config.DockerBin }

// derived from all the context processing (IMMUTABLE SNAPSHOTS)
func (ctx AppContext) CommonArgs() ilist.List[string]    { return ctx.commonArgs }
func (ctx AppContext) BuildArgs() ilist.List[string]     { return ctx.buildArgs }
func (ctx AppContext) RunArgs() ilist.List[string]       { return ctx.runArgs }
func (ctx AppContext) Cmds() ilist.List[string]          { return ctx.cmds }
func (ctx AppContext) KeepaliveArgs() ilist.List[string] { return ctx.keepaliveArgs }
func (ctx AppContext) TtyArgs() ilist.List[string]       { return ctx.ttyArgs }

// ToBuilder converts an immutable AppContext back into a mutable builder.
func (ctx AppContext) ToBuilder() *AppContextBuilder {
	b := cloneAppContextBuilder(&ctx.values)

	b.CommonArgs = ctx.commonArgs.ToBuilder()
	b.BuildArgs = ctx.buildArgs.ToBuilder()
	b.RunArgs = ctx.runArgs.ToBuilder()
	b.Cmds = ctx.cmds.ToBuilder()
	b.KeepaliveArgs = ctx.keepaliveArgs.ToBuilder()
	b.TtyArgs = ctx.ttyArgs.ToBuilder()

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

	fmt.Fprintf(&str, "# General configuration ---------\n")
	fmt.Fprintf(&str, "    ConfigFile:       %q\n", ctx.ConfigFile())
	fmt.Fprintf(&str, "    WorkspacePath:    %q\n", ctx.WorkspacePath())

	fmt.Fprintf(&str, "# Flags -------------------------\n")
	fmt.Fprintf(&str, "    Dryrun:           %t\n", ctx.Dryrun())
	fmt.Fprintf(&str, "    Verbose:          %t\n", ctx.Verbose())
	fmt.Fprintf(&str, "    Keepalive:        %t\n", ctx.Keepalive())
	fmt.Fprintf(&str, "    SilenceBuild:     %t\n", ctx.SilenceBuild())
	fmt.Fprintf(&str, "    Daemon:           %t\n", ctx.Daemon())
	fmt.Fprintf(&str, "    DoPull:           %t\n", ctx.DoPull())
	fmt.Fprintf(&str, "    Dind:             %t\n", ctx.Dind())

	fmt.Fprintf(&str, "# Image Configuration -----------\n")
	fmt.Fprintf(&str, "    DockerFile:       %q\n", ctx.DockerFile())
	fmt.Fprintf(&str, "    ImageName:        %q\n", ctx.ImageName())
	fmt.Fprintf(&str, "    Variant:          %q\n", ctx.Variant())
	fmt.Fprintf(&str, "    Version:          %q\n", ctx.Version())

	fmt.Fprintf(&str, "# Runtime values ----------------\n")
	fmt.Fprintf(&str, "    ProjectName:      %q\n", ctx.ProjectName())
	fmt.Fprintf(&str, "    HostUID:          %q\n", ctx.HostUID())
	fmt.Fprintf(&str, "    HostGID:          %q\n", ctx.HostGID())
	fmt.Fprintf(&str, "    Timezone:         %q\n", ctx.Timezone())

	fmt.Fprintf(&str, "# Container Configuration -------\n")
	fmt.Fprintf(&str, "    ContainerName:    %q\n", ctx.ContainerName())
	fmt.Fprintf(&str, "    WorkspacePort:    %q\n", ctx.WorkspacePort())
	fmt.Fprintf(&str, "    HostPort:         %q\n", ctx.HostPort())
	fmt.Fprintf(&str, "    ContainerEnvFile: %q\n", ctx.ContainerEnvFile())

	fmt.Fprintf(&str, "# Docker-in-Docker --------------\n")
	fmt.Fprintf(&str, "    DindNet:          %q\n", ctx.DindNet())
	fmt.Fprintf(&str, "    DindName:         %q\n", ctx.DindName())
	fmt.Fprintf(&str, "    DockerBin:        %q\n", ctx.DockerBin())

	fmt.Fprintf(&str, "# Lists (Immutable) -------------\n")
	formatList(&str, "CommonArgs", ctx.CommonArgs(), "    ")
	formatList(&str, "BuildArgs", ctx.BuildArgs(), "    ")
	formatList(&str, "RunArgs", ctx.RunArgs(), "    ")
	formatList(&str, "Cmds", ctx.Cmds(), "    ")
	formatList(&str, "KeepaliveArgs", ctx.KeepaliveArgs(), "    ")
	formatList(&str, "TtyArgs", ctx.TtyArgs(), "    ")

	str.WriteString("==================================================================\n")

	return str.String()
}
