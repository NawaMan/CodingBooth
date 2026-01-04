// Package appctx provides centralized application context for workspace configuration and state.
//
// AppContext is an immutable snapshot (like List), AppContextBuilder is mutable (like AppendableList).
// Use ToBuilder() and Build() to convert between them.
package appctx

import "github.com/nawaman/workspace/src/pkg/ilist"

type AppConfig struct {

	// General configuration
	ConfigFile    string `toml:"ConfigFile,omitempty"`
	WorkspacePath string `toml:"WorkspacePath,omitempty"`

	// Flags
	Dryrun       bool `toml:"Dryrun,omitempty"`
	Verbose      bool `toml:"Verbose,omitempty"`
	Keepalive    bool `toml:"Keepalive,omitempty"`
	SilenceBuild bool `toml:"SilenceBuild,omitempty"`
	Daemon       bool `toml:"Daemon,omitempty"`
	DoPull       bool `toml:"DoPull,omitempty"`
	Dind         bool `toml:"Dind,omitempty"`

	// Image Configuration
	DockerFile string `toml:"DockerFile,omitempty"`
	ImageName  string `toml:"ImageName,omitempty"`
	Variant    string `toml:"Variant,omitempty"`
	Version    string `toml:"Version,omitempty"`

	// Runtime values
	ProjectName string `toml:"ProjectName,omitempty"`
	HostUID     string `toml:"HostUID,omitempty"`
	HostGID     string `toml:"HostGID,omitempty"`
	Timezone    string `toml:"Timezone,omitempty"`

	// Container Configuration
	ContainerName    string `toml:"ContainerName,omitempty"`
	WorkspacePort    string `toml:"WorkspacePort,omitempty"`
	HostPort         string `toml:"HostPort,omitempty"`
	ContainerEnvFile string `toml:"ContainerEnvFile,omitempty"`

	// Docker-in-Docker
	DindNet   string `toml:"DindNet,omitempty"`
	DindName  string `toml:"DindName,omitempty"`
	DockerBin string `toml:"DockerBin,omitempty"`

	// TOML-friendly array fields (temporary storage during decode)
	CommonArgsSlice    []string `toml:"CommonArgs,omitempty"`
	BuildArgsSlice     []string `toml:"BuildArgs,omitempty"`
	RunArgsSlice       []string `toml:"RunArgs,omitempty"`
	CmdsSlice          []string `toml:"Cmds,omitempty"`
	KeepaliveArgsSlice []string `toml:"KeepaliveArgs,omitempty"`
	TtyArgsSlice       []string `toml:"TtyArgs,omitempty"`
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

// NewAppContextBuilder creates a new AppContextBuilder with all mutable lists initialized.
func NewAppContextBuilder() *AppContextBuilder {
	return &AppContextBuilder{
		CommonArgs:    ilist.NewAppendableList[string](),
		BuildArgs:     ilist.NewAppendableList[string](),
		RunArgs:       ilist.NewAppendableList[string](),
		Cmds:          ilist.NewAppendableList[string](),
		KeepaliveArgs: ilist.NewAppendableList[string](),
		TtyArgs:       ilist.NewAppendableList[string](),
	}
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
	copy.KeepaliveArgsSlice = append([]string(nil), config.KeepaliveArgsSlice...)
	copy.TtyArgsSlice = append([]string(nil), config.TtyArgsSlice...)

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

func cloneAppendableList(list *ilist.AppendableList[string]) *ilist.AppendableList[string] {
	if list == nil {
		return ilist.NewAppendableList[string]()
	}
	return list.Clone()
}

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
