package appctx

import (
	"github.com/BurntSushi/toml"
	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"github.com/nawaman/workspace/src/pkg/nillable"
)

type AppConfig struct {

	// --------------------
	// General configuration
	// --------------------
	Dryrun    nillable.NillableBool   `toml:"dryrun,omitempty"    envconfig:"WS_DRYRUN" default:"false"`
	Verbose   nillable.NillableBool   `toml:"verbose,omitempty"   envconfig:"WS_VERBOSE" default:"false"`
	Config    nillable.NillableString `toml:"config,omitempty"    envconfig:"WS_CONFIG" default:"./ws--config.toml"`
	Workspace nillable.NillableString `toml:"workspace,omitempty" envconfig:"WS_WORKSPACE"`

	// --------------------
	// Flags
	// --------------------
	KeepAlive    bool `toml:"keep-alive,omitempty"    envconfig:"WS_KEEP_ALIVE" default:"false"`
	SilenceBuild bool `toml:"silence-build,omitempty" envconfig:"WS_SILENCE_BUILD" default:"false"`
	Daemon       bool `toml:"daemon,omitempty"        envconfig:"WS_DAEMON" default:"false"`
	Pull         bool `toml:"pull,omitempty"          envconfig:"WS_PULL" default:"false"`
	Dind         bool `toml:"dind,omitempty"          envconfig:"WS_DIND" default:"false"`

	// --------------------
	// Image configuration
	// --------------------
	Dockerfile string `toml:"dockerfile,omitempty" envconfig:"WS_DOCKERFILE"`
	Image      string `toml:"image,omitempty"      envconfig:"WS_IMAGE"`
	Variant    string `toml:"variant,omitempty"    envconfig:"WS_VARIANT" default:"default"`
	Version    string `toml:"version,omitempty"    envconfig:"WS_VERSION" default:"latest"`

	// --------------------
	// Runtime values
	// --------------------
	ProjectName string `toml:"project-name,omitempty" envconfig:"WS_PROJECT_NAME"`
	HostUID     string `toml:"host-uid,omitempty"     envconfig:"WS_HOST_UID"`
	HostGID     string `toml:"host-gid,omitempty"     envconfig:"WS_HOST_GID"`
	Timezone    string `toml:"timezone,omitempty"     envconfig:"WS_TIMEZONE"`

	// --------------------
	// Container configuration
	// --------------------
	Name    string `toml:"name,omitempty"      envconfig:"WS_NAME"`
	Port    string `toml:"port,omitempty"      envconfig:"WS_PORT" default:"NEXT"`
	EnvFile string `toml:"env-file,omitempty"  envconfig:"WS_ENV_FILE"`

	// --------------------
	// TOML-friendly array fields
	// --------------------
	CommonArgs ilist.SemicolonStringList `toml:"common-args,omitempty" envconfig:"WS_COMMON_ARGS"`
	BuildArgs  ilist.SemicolonStringList `toml:"build-args,omitempty"  envconfig:"WS_BUILD_ARGS"`
	RunArgs    ilist.SemicolonStringList `toml:"run-args,omitempty"    envconfig:"WS_RUN_ARGS"`
	Cmds       ilist.SemicolonStringList `toml:"cmds,omitempty"        envconfig:"WS_CMDS"`
}

// Clone the content of the app config.
func (config *AppConfig) Clone() *AppConfig {
	copy := *config

	copy.CommonArgs = config.CommonArgs.Clone()
	copy.BuildArgs = config.BuildArgs.Clone()
	copy.RunArgs = config.RunArgs.Clone()
	copy.Cmds = config.Cmds.Clone()

	return &copy
}

// ReadFromEnvVars reads configuration from environment variables and populates the config (overriding existing values).
func ReadFromEnvVars(config *AppConfig) error {
	return envconfig.Process("", config)
}

// ReadFromToml reads configuration from a TOML file and populates the config (overriding existing values).
func ReadFromToml(path string, config *AppConfig) error {
	if _, err := toml.DecodeFile(path, config); err != nil {
		return err
	}
	return nil
}
