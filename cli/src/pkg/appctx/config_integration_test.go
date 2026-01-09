package appctx_test

import (
	"os"
	"testing"

	"github.com/nawaman/workspace/cli/src/pkg/appctx"
	"github.com/stretchr/testify/assert"
)

func TestIntegration_ReadFromEnvVars(t *testing.T) {
	// Setup environment variables
	envVars := map[string]string{
		"WS_VERBOSE":      "true",
		"WS_PROJECT_NAME": "integration-test-project",
		"WS_HOST_UID":     "1001",
	}

	for k, v := range envVars {
		os.Setenv(k, v)
		defer os.Unsetenv(k)
	}

	// Create a clean config
	config := appctx.AppConfig{}

	// Call the function under test
	err := appctx.ReadFromEnvVars(&config)
	assert.NoError(t, err)

	// Verify results
	assert.True(t, config.Verbose.ValueOr(false))
	assert.Equal(t, "integration-test-project", config.ProjectName)
	assert.Equal(t, "1001", config.HostUID)
}

func TestIntegration_ReadFromToml(t *testing.T) {
	// Create a temporary TOML file
	tomlContent := `
verbose = true
project-name = "toml-test-project"
host-uid = "1002"
`
	tmpfile, err := os.CreateTemp("", "config-*.toml")
	assert.NoError(t, err)
	defer os.Remove(tmpfile.Name())

	_, err = tmpfile.Write([]byte(tomlContent))
	assert.NoError(t, err)
	tmpfile.Close()

	// Create a clean config
	config := appctx.AppConfig{}

	// Call the function under test
	err = appctx.ReadFromToml(tmpfile.Name(), &config)
	assert.NoError(t, err)

	// Verify results
	assert.True(t, config.Verbose.ValueOr(false))
	assert.Equal(t, "toml-test-project", config.ProjectName)
	assert.Equal(t, "1002", config.HostUID)
}
