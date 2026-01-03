package appctx

import "github.com/nawaman/workspace/src/pkg/ilist"

// AppContextBuilder is a mutable builder for constructing AppContext instances.
// All fields are public for direct access and can be loaded from TOML configuration.
type AppContextBuilder struct {
	// Version & Paths
	WsVersion     string `toml:"WsVersion,omitempty"`
	ScriptName    string `toml:"ScriptName,omitempty"`
	ScriptDir     string `toml:"ScriptDir,omitempty"`
	LibDir        string `toml:"LibDir,omitempty"`
	PrebuildRepo  string `toml:"PrebuildRepo,omitempty"`
	SetupsDir     string `toml:"SetupsDir,omitempty"`
	WorkspacePath string `toml:"WorkspacePath,omitempty"`
	ProjectName   string `toml:"ProjectName,omitempty"`

	// User & Environment
	HostUID  string `toml:"HostUID,omitempty"`
	HostGID  string `toml:"HostGID,omitempty"`
	Timezone string `toml:"Timezone,omitempty"`

	// Flags
	Dryrun         bool `toml:"Dryrun,omitempty"`
	Verbose        bool `toml:"Verbose,omitempty"`
	Keepalive      bool `toml:"Keepalive,omitempty"`
	SilenceBuild   bool `toml:"SilenceBuild,omitempty"`
	Daemon         bool `toml:"Daemon,omitempty"`
	DoPull         bool `toml:"DoPull,omitempty"`
	LocalBuild     bool `toml:"LocalBuild,omitempty"`
	SetConfigFile  bool `toml:"SetConfigFile,omitempty"`
	HasNotebook    bool `toml:"HasNotebook,omitempty"`
	HasVscode      bool `toml:"HasVscode,omitempty"`
	HasDesktop     bool `toml:"HasDesktop,omitempty"`
	Dind           bool `toml:"Dind,omitempty"`
	CreatedDindNet bool `toml:"CreatedDindNet,omitempty"`

	// Image Configuration
	DockerFile string `toml:"DockerFile,omitempty"`
	ImageName  string `toml:"ImageName,omitempty"`
	ImageMode  string `toml:"ImageMode,omitempty"`
	Variant    string `toml:"Variant,omitempty"`
	Version    string `toml:"Version,omitempty"`

	// Container Configuration
	ContainerName    string `toml:"ContainerName,omitempty"`
	WorkspacePort    string `toml:"WorkspacePort,omitempty"`
	HostPort         string `toml:"HostPort,omitempty"`
	PortGenerated    bool   `toml:"PortGenerated,omitempty"`
	ContainerEnvFile string `toml:"ContainerEnvFile,omitempty"`
	ConfigFile       string `toml:"ConfigFile,omitempty"`
	FileNotUsed      string `toml:"FileNotUsed,omitempty"`

	// Docker-in-Docker
	DindNet   string `toml:"DindNet,omitempty"`
	DindName  string `toml:"DindName,omitempty"`
	DockerBin string `toml:"DockerBin,omitempty"`

	// Runtime State
	RunMode string `toml:"RunMode,omitempty"`

	// Argument Lists (mutable builders)
	// Note: These are pointers, so TOML will decode into []string and we'll convert
	CommonArgs    *ilist.AppendableList[string] `toml:"-"` // Handled specially
	BuildArgs     *ilist.AppendableList[string] `toml:"-"` // Handled specially
	RunArgs       *ilist.AppendableList[string] `toml:"-"` // Handled specially
	Cmds          *ilist.AppendableList[string] `toml:"-"` // Handled specially
	KeepaliveArgs *ilist.AppendableList[string] `toml:"-"` // Handled specially
	TtyArgs       *ilist.AppendableList[string] `toml:"-"` // Handled specially

	// TOML-friendly array fields (temporary storage during decode)
	CommonArgsSlice    []string `toml:"CommonArgs,omitempty"`
	BuildArgsSlice     []string `toml:"BuildArgs,omitempty"`
	RunArgsSlice       []string `toml:"RunArgs,omitempty"`
	CmdsSlice          []string `toml:"Cmds,omitempty"`
	KeepaliveArgsSlice []string `toml:"KeepaliveArgs,omitempty"`
	TtyArgsSlice       []string `toml:"TtyArgs,omitempty"`
}

// NewAppContextBuilder creates a new AppContextBuilder with defaults matching workspace.sh initialization.
func NewAppContextBuilder(wsVersion string) *AppContextBuilder {
	return &AppContextBuilder{
		// Version & Paths
		WsVersion:    wsVersion,
		PrebuildRepo: "nawaman/workspace",
		FileNotUsed:  "none",
		SetupsDir:    "/opt/workspace/setups",

		// Flags
		Dryrun:       false,
		Verbose:      false,
		Keepalive:    false,
		SilenceBuild: false,
		Daemon:       false,
		DoPull:       false,
		LocalBuild:   false,
		HasNotebook:  false,
		HasVscode:    false,
		HasDesktop:   false,
		Dind:         false,

		// Image Configuration
		Variant: "default",
		Version: "latest",

		// Container Configuration
		WorkspacePort: "NEXT",

		// Initialize builders
		CommonArgs:    ilist.NewAppendableList[string](),
		BuildArgs:     ilist.NewAppendableList[string](),
		RunArgs:       ilist.NewAppendableList[string](),
		Cmds:          ilist.NewAppendableList[string](),
		KeepaliveArgs: ilist.NewAppendableList[string](),
		TtyArgs:       ilist.NewAppendableList[string](),
	}
}

// Build creates an immutable AppContext snapshot from this builder.
func (builder *AppContextBuilder) Build() AppContext {
	return AppContext{
		// Version & Paths
		wsVersion:     builder.WsVersion,
		scriptName:    builder.ScriptName,
		scriptDir:     builder.ScriptDir,
		libDir:        builder.LibDir,
		prebuildRepo:  builder.PrebuildRepo,
		setupsDir:     builder.SetupsDir,
		workspacePath: builder.WorkspacePath,
		projectName:   builder.ProjectName,

		// User & Environment
		hostUID:  builder.HostUID,
		hostGID:  builder.HostGID,
		timezone: builder.Timezone,

		// Flags
		dryrun:         builder.Dryrun,
		verbose:        builder.Verbose,
		keepalive:      builder.Keepalive,
		silenceBuild:   builder.SilenceBuild,
		daemon:         builder.Daemon,
		doPull:         builder.DoPull,
		localBuild:     builder.LocalBuild,
		setConfigFile:  builder.SetConfigFile,
		hasNotebook:    builder.HasNotebook,
		hasVscode:      builder.HasVscode,
		hasDesktop:     builder.HasDesktop,
		dind:           builder.Dind,
		createdDindNet: builder.CreatedDindNet,

		// Image Configuration
		dockerFile: builder.DockerFile,
		imageName:  builder.ImageName,
		imageMode:  builder.ImageMode,
		variant:    builder.Variant,
		version:    builder.Version,

		// Container Configuration
		containerName:    builder.ContainerName,
		workspacePort:    builder.WorkspacePort,
		hostPort:         builder.HostPort,
		portGenerated:    builder.PortGenerated,
		containerEnvFile: builder.ContainerEnvFile,
		configFile:       builder.ConfigFile,
		fileNotUsed:      builder.FileNotUsed,

		// Docker-in-Docker
		dindNet:   builder.DindNet,
		dindName:  builder.DindName,
		dockerBin: builder.DockerBin,

		// Runtime State
		runMode: builder.RunMode,

		// Argument Lists (snapshot to immutable)
		commonArgs:    builder.CommonArgs.Snapshot(),
		buildArgs:     builder.BuildArgs.Snapshot(),
		runArgs:       builder.RunArgs.Snapshot(),
		cmds:          builder.Cmds.Snapshot(),
		keepaliveArgs: builder.KeepaliveArgs.Snapshot(),
		ttyArgs:       builder.TtyArgs.Snapshot(),
	}
}

// Helper methods for appending to argument lists (for convenience)

// AppendCommonArg adds arguments to the common args builder.
func (builder *AppContextBuilder) AppendCommonArg(args ...string) {
	builder.CommonArgs.Append(args...)
}

// AppendBuildArg adds arguments to the build args builder.
func (builder *AppContextBuilder) AppendBuildArg(args ...string) {
	builder.BuildArgs.Append(args...)
}

// AppendRunArg adds arguments to the run args builder.
func (builder *AppContextBuilder) AppendRunArg(args ...string) {
	builder.RunArgs.Append(args...)
}

// AppendCmd adds commands to the cmds builder.
func (builder *AppContextBuilder) AppendCmd(cmds ...string) {
	builder.Cmds.Append(cmds...)
}

// ApplySlicesToLists converts the TOML-decoded slice fields into AppendableList instances.
// This should be called after TOML decoding to populate the list fields from config.
func (builder *AppContextBuilder) ApplySlicesToLists() {
	if builder.CommonArgsSlice != nil {
		builder.CommonArgs.Append(builder.CommonArgsSlice...)
	}
	if builder.BuildArgsSlice != nil {
		builder.BuildArgs.Append(builder.BuildArgsSlice...)
	}
	if builder.RunArgsSlice != nil {
		builder.RunArgs.Append(builder.RunArgsSlice...)
	}
	if builder.CmdsSlice != nil {
		builder.Cmds.Append(builder.CmdsSlice...)
	}
	if builder.KeepaliveArgsSlice != nil {
		builder.KeepaliveArgs.Append(builder.KeepaliveArgsSlice...)
	}
	if builder.TtyArgsSlice != nil {
		builder.TtyArgs.Append(builder.TtyArgsSlice...)
	}
}
