// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestIntegration_FullPipeline tests the full parse → compile pipeline.
func TestIntegration_FullPipeline(t *testing.T) {
	t.Run("realistic Django project Boothfile", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# Django development environment

# System dependencies
run apt-get update && apt-get install -y libpq-dev

# Python setup
setup python 3.12

# Python packages
install pip django djangorestframework psycopg2-binary gunicorn

# Project configuration
copy ./requirements.txt /tmp/requirements.txt
env DJANGO_SETTINGS_MODULE=myproject.settings
env DEBUG=true

# Expose Django port
expose 8000
`
		result := CompileString(content)

		require.False(t, result.HasErrors(), "errors: %v", result.Errors)

		df := result.Dockerfile

		// Check prologue
		assert.Contains(t, df, "# syntax=docker/dockerfile:1.7")
		assert.Contains(t, df, "FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}")

		// Check commands in order
		lines := strings.Split(df, "\n")
		var commands []string
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") {
				commands = append(commands, line)
			}
		}

		// Verify order and content
		foundAptGet := false
		foundPython := false
		foundPip := false
		foundCopy := false
		foundEnv := false
		foundExpose := false

		for i, cmd := range commands {
			if strings.Contains(cmd, "apt-get update") {
				foundAptGet = true
			}
			if strings.Contains(cmd, "python--setup.sh 3.12") {
				foundPython = true
				assert.True(t, foundAptGet, "apt-get should come before python setup")
			}
			if strings.Contains(cmd, "pip--install.sh django") {
				foundPip = true
				assert.True(t, foundPython, "python setup should come before pip install")
			}
			if strings.Contains(cmd, "COPY ./requirements.txt") {
				foundCopy = true
			}
			if strings.Contains(cmd, "ENV DJANGO_SETTINGS_MODULE") {
				foundEnv = true
			}
			if strings.Contains(cmd, "EXPOSE 8000") {
				foundExpose = true
			}
			_ = i
		}

		assert.True(t, foundAptGet, "should have apt-get command")
		assert.True(t, foundPython, "should have python setup")
		assert.True(t, foundPip, "should have pip install")
		assert.True(t, foundCopy, "should have copy command")
		assert.True(t, foundEnv, "should have env command")
		assert.True(t, foundExpose, "should have expose command")
	})

	t.Run("Java/Maven project Boothfile", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# Java development environment
arg JAVA_VERSION=21

setup jdk ${JAVA_VERSION} temurin
setup mvn 3.9.6

copy pom.xml /tmp/pom.xml
env MAVEN_OPTS=-Xmx1024m
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile

		assert.Contains(t, df, "ARG JAVA_VERSION=21")
		assert.Contains(t, df, "RUN jdk--setup.sh ${JAVA_VERSION} temurin")
		assert.Contains(t, df, "RUN mvn--setup.sh 3.9.6")
		assert.Contains(t, df, "COPY pom.xml /tmp/pom.xml")
		assert.Contains(t, df, "ENV MAVEN_OPTS=-Xmx1024m")
	})

	t.Run("Node.js project Boothfile", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# Node.js development environment
setup nodejs 20

install npm express lodash typescript

copy package.json /app/package.json
workdir /app
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile
		assert.Contains(t, df, "RUN nodejs--setup.sh 20")
		assert.Contains(t, df, "RUN npm--install.sh express lodash typescript")
		assert.Contains(t, df, "COPY package.json /app/package.json")
		assert.Contains(t, df, "WORKDIR /app")
	})
}

// TestIntegration_HeredocModes tests all heredoc modes in realistic scenarios.
func TestIntegration_HeredocModes(t *testing.T) {
	t.Run("verbatim mode for complex script", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

run <<SCRIPT
set -e
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Running on $NAME $VERSION"
fi
apt-get update
apt-get install -y curl wget
SCRIPT
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile
		assert.Contains(t, df, "RUN <<SCRIPT")
		assert.Contains(t, df, "set -e")
		assert.Contains(t, df, "if [ -f /etc/os-release ]; then")
		assert.Contains(t, df, "SCRIPT")
	})

	t.Run("and-join mode for package installation", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

run &&<<INSTALL
apt-get update
apt-get install -y curl wget jq
rm -rf /var/lib/apt/lists/*
INSTALL
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile
		// Should be joined with &&
		assert.Contains(t, df, "&&")
		assert.Contains(t, df, "apt-get update")
		assert.Contains(t, df, "apt-get install -y curl wget jq")
		assert.Contains(t, df, "rm -rf /var/lib/apt/lists/*")
		// Should NOT have INSTALL delimiter (it's processed)
		assert.NotContains(t, df, "<<INSTALL")
	})

	t.Run("semi-join mode for optional commands", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

run ;<<CLEANUP
rm -f /tmp/optional-file
rm -f /tmp/another-optional
echo "cleanup done"
CLEANUP
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile
		// Should be joined with ;
		assert.Contains(t, df, ";")
		assert.Contains(t, df, "rm -f /tmp/optional-file")
	})
}

// TestIntegration_CustomSetupScripts tests custom setup script detection.
func TestIntegration_CustomSetupScripts(t *testing.T) {
	t.Run("custom setup script adds COPY", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

setup mycompany-tools
setup python 3.12
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		require.False(t, parseResult.HasErrors())

		// Compiler with custom setups directory
		compiler := NewCompilerWithOptions(CompilerOptions{
			CustomSetupsDir: ".booth/setups",
			HasCustomSetups: true,
		})

		result := compiler.Compile(parseResult)

		require.False(t, result.HasErrors())

		df := result.Dockerfile

		// Custom setups dir should be copied once in prologue
		assert.Contains(t, df, "COPY .booth/setups/ /home/coder/.booth/setups/")
		assert.Contains(t, df, "ENV PATH=/home/coder/.booth/setups:$PATH")

		// Both setup commands generate RUN (scripts found via PATH)
		assert.Contains(t, df, "RUN mycompany-tools--setup.sh")
		assert.Contains(t, df, "RUN python--setup.sh 3.12")

		// Only one COPY (for the whole setups directory)
		copyCount := strings.Count(df, "COPY")
		assert.Equal(t, 1, copyCount, "should only have one COPY for setups directory")
	})
}

// TestIntegration_ErrorRecovery tests error handling and recovery.
func TestIntegration_ErrorRecovery(t *testing.T) {
	t.Run("multiple errors reported", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

unknown_cmd1 foo
unknown_cmd2 bar
run echo hello
unknown_cmd3 baz
`
		result := CompileString(content)

		assert.True(t, result.HasErrors())
		// Should report all unknown commands
		assert.GreaterOrEqual(t, len(result.Errors), 3)
	})

	t.Run("valid commands still compiled despite earlier errors", func(t *testing.T) {
		// Parser should continue after errors
		content := `run echo hello
`
		parser := NewParser()
		result := parser.ParseString(content)

		// Should have error about missing syntax directive
		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Missing syntax directive")

		// But should still have parsed the run command
		foundRun := false
		for _, cmd := range result.Commands {
			if cmd.Type == CommandRun {
				foundRun = true
			}
		}
		assert.True(t, foundRun, "should have parsed run command despite syntax error")
	})
}

// TestIntegration_EdgeCases tests edge cases and boundary conditions.
func TestIntegration_EdgeCases(t *testing.T) {
	t.Run("empty Boothfile (only syntax)", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		// Should have prologue but no additional commands
		assert.Contains(t, result.Dockerfile, "FROM nawaman/codingbooth")
	})

	t.Run("Boothfile with only comments", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# This is just a comment file
# No actual commands

# More comments
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		// Should compile with just prologue
		assert.Contains(t, result.Dockerfile, "FROM nawaman/codingbooth")
	})

	t.Run("very long command line", func(t *testing.T) {
		packages := "pkg1 pkg2 pkg3 pkg4 pkg5 pkg6 pkg7 pkg8 pkg9 pkg10 pkg11 pkg12 pkg13 pkg14 pkg15"
		content := `# syntax=codingbooth/boothfile:1

install pip ` + packages + `
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "pip--install.sh "+packages)
	})

	t.Run("special characters in arguments", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

env DATABASE_URL=postgres://user:pass@host:5432/db?sslmode=require
label description="My App - v1.0 (beta)"
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "ENV DATABASE_URL=postgres://user:pass@host:5432/db?sslmode=require")
		assert.Contains(t, result.Dockerfile, `LABEL description="My App - v1.0 (beta)"`)
	})
}

// TestIntegration_RealWorldExamples tests real-world Boothfile patterns.
func TestIntegration_RealWorldExamples(t *testing.T) {
	t.Run("data science environment", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# Data Science Booth

# System dependencies for scientific computing
run &&<<APT
apt-get update
apt-get install -y libopenblas-dev liblapack-dev gfortran
rm -rf /var/lib/apt/lists/*
APT

# Python with scientific stack
setup python 3.11
install pip numpy pandas scipy matplotlib seaborn scikit-learn jupyter

# Jupyter configuration
env JUPYTER_TOKEN=mysecrettoken
expose 8888
`
		result := CompileString(content)

		require.False(t, result.HasErrors(), "errors: %v", result.Errors)

		df := result.Dockerfile
		assert.Contains(t, df, "libopenblas-dev")
		assert.Contains(t, df, "python--setup.sh 3.11")
		assert.Contains(t, df, "pip--install.sh numpy pandas scipy matplotlib seaborn scikit-learn jupyter")
		assert.Contains(t, df, "EXPOSE 8888")
	})

	t.Run("microservices Go environment", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1

# Go Microservices Development

arg GO_VERSION=1.22

setup go ${GO_VERSION}

# Development tools
run go install github.com/air-verse/air@latest
run go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

env CGO_ENABLED=0
env GOOS=linux
workdir /app
`
		result := CompileString(content)

		require.False(t, result.HasErrors())

		df := result.Dockerfile
		assert.Contains(t, df, "ARG GO_VERSION=1.22")
		assert.Contains(t, df, "go--setup.sh ${GO_VERSION}")
		assert.Contains(t, df, "go install github.com/air-verse/air@latest")
		assert.Contains(t, df, "ENV CGO_ENABLED=0")
	})
}
