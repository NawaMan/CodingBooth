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

func TestCompiler_Prologue(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
`
	result := CompileString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)

	// Check prologue components
	assert.Contains(t, result.Dockerfile, "# syntax=docker/dockerfile:1.7")
	assert.Contains(t, result.Dockerfile, "ARG BOOTH_VARIANT_TAG=base")
	assert.Contains(t, result.Dockerfile, "ARG BOOTH_VERSION_TAG=latest")
	assert.Contains(t, result.Dockerfile, "FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}")
	// SHELL, USER, and WORKDIR are already set in the base image
}

func TestCompiler_Run(t *testing.T) {
	t.Run("simple run", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run apt-get update
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN apt-get update")
	})

	t.Run("run with chain", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run apt-get update && apt-get install -y curl
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN apt-get update && apt-get install -y curl")
	})
}

func TestCompiler_HeredocVerbatim(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run <<END
set -e
apt-get update
apt-get install -y curl
END
`
	result := CompileString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
	assert.Contains(t, result.Dockerfile, "RUN <<END")
	assert.Contains(t, result.Dockerfile, "set -e")
	assert.Contains(t, result.Dockerfile, "apt-get update")
	assert.Contains(t, result.Dockerfile, "apt-get install -y curl")
	// Check that END delimiter is present at the end
	lines := strings.Split(result.Dockerfile, "\n")
	foundEndDelimiter := false
	for _, line := range lines {
		if strings.TrimSpace(line) == "END" {
			foundEndDelimiter = true
			break
		}
	}
	assert.True(t, foundEndDelimiter, "should have END delimiter")
}

func TestCompiler_HeredocAndJoin(t *testing.T) {
	t.Run("simple join", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run &&<<END
apt-get update
apt-get install -y curl
rm -rf /var/lib/apt/lists/*
END
`
		result := CompileString(content)

		assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
		// Should contain && joiner
		assert.Contains(t, result.Dockerfile, "&&")
		assert.Contains(t, result.Dockerfile, "apt-get update")
		assert.Contains(t, result.Dockerfile, "apt-get install -y curl")
		assert.Contains(t, result.Dockerfile, "rm -rf /var/lib/apt/lists/*")
	})

	t.Run("with line continuations", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run &&<<END
apt-get update
apt-get install -y \
    curl \
    wget
rm -rf /var/lib/apt/lists/*
END
`
		result := CompileString(content)

		assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
		// Line continuations should be collapsed - check all parts are present
		assert.Contains(t, result.Dockerfile, "apt-get install -y")
		assert.Contains(t, result.Dockerfile, "curl")
		assert.Contains(t, result.Dockerfile, "wget")
		// And they should be joined, not separate RUN commands
		assert.Equal(t, 1, strings.Count(result.Dockerfile, "RUN apt-get"))
	})

	t.Run("with comments stripped", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run &&<<END
apt-get update
# This comment should be stripped
apt-get install -y curl
END
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		// Comment should not appear in output
		assert.NotContains(t, result.Dockerfile, "This comment should be stripped")
	})

	t.Run("with blank lines stripped", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run &&<<END
apt-get update

apt-get install -y curl
END
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		// Should only have 2 commands joined with &&
		df := result.Dockerfile
		// Count occurrences of &&
		andCount := strings.Count(df, "&&")
		assert.Equal(t, 1, andCount, "should have exactly one && joining two commands")
	})
}

func TestCompiler_HeredocSemiJoin(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run ;<<END
rm -f /tmp/optional
echo "continuing"
END
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, ";")
	assert.Contains(t, result.Dockerfile, "rm -f /tmp/optional")
	assert.Contains(t, result.Dockerfile, `echo "continuing"`)
}

func TestCompiler_Copy(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "COPY ./config /opt/config")
	assert.Contains(t, result.Dockerfile, "COPY requirements.txt /tmp/requirements.txt")
}

func TestCompiler_Env(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
env MY_VAR=value
env APP_ENV=production
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "ENV MY_VAR=value")
	assert.Contains(t, result.Dockerfile, "ENV APP_ENV=production")
}

func TestCompiler_Workdir(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
workdir /app
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "WORKDIR /app")
}

func TestCompiler_Expose(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
expose 8080
expose 3000 4000
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "EXPOSE 8080")
	assert.Contains(t, result.Dockerfile, "EXPOSE 3000 4000")
}

func TestCompiler_Label(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
label maintainer="team@example.com"
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, `LABEL maintainer="team@example.com"`)
}

func TestCompiler_Arg(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
arg NODE_VERSION=20
arg PYTHON_VERSION
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "ARG NODE_VERSION=20")
	assert.Contains(t, result.Dockerfile, "ARG PYTHON_VERSION")
}

func TestCompiler_Setup(t *testing.T) {
	t.Run("setup without args", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup python
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN python--setup.sh")
	})

	t.Run("setup with version", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup python 3.12
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN python--setup.sh 3.12")
	})

	t.Run("setup with multiple args", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup jdk 21 temurin
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN jdk--setup.sh 21 temurin")
	})
}

func TestCompiler_WithCustomSetupsDir(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
setup myapp
`
	parser := NewParser()
	parseResult := parser.ParseString(content)

	// Compiler with custom setups directory
	compiler := NewCompilerWithOptions(CompilerOptions{
		CustomSetupsDir: ".booth/setups",
		HasCustomSetups: true,
	})

	result := compiler.Compile(parseResult)

	assert.False(t, result.HasErrors())
	// Custom setups dir should be copied in prologue
	assert.Contains(t, result.Dockerfile, "COPY .booth/setups/ /home/coder/.booth/setups/")
	// PATH should be updated in prologue
	assert.Contains(t, result.Dockerfile, "ENV PATH=/home/coder/.booth/setups:$PATH")
	// Setup command generates RUN (script is found via PATH)
	assert.Contains(t, result.Dockerfile, "RUN myapp--setup.sh")
}

func TestCompiler_Install(t *testing.T) {
	t.Run("install single package", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install pip django
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN pip--install.sh django")
	})

	t.Run("install multiple packages", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install pip django djangorestframework psycopg2-binary
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN pip--install.sh django djangorestframework psycopg2-binary")
	})

	t.Run("install npm packages", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install npm express lodash
`
		result := CompileString(content)

		assert.False(t, result.HasErrors())
		assert.Contains(t, result.Dockerfile, "RUN npm--install.sh express lodash")
	})
}

func TestCompiler_DockerEscapeHatch(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
DOCKER HEALTHCHECK CMD curl -f http://localhost/ || exit 1
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	assert.Contains(t, result.Dockerfile, "HEALTHCHECK CMD curl -f http://localhost/ || exit 1")
	// Should NOT have the DOCKER prefix
	assert.NotContains(t, result.Dockerfile, "DOCKER HEALTHCHECK")
}

func TestCompiler_CommentsPreserved(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
# This is a comment
run echo hello
# Another comment
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())
	// Comments should be preserved for readability (except syntax directive which transforms)
	assert.Contains(t, result.Dockerfile, "# This is a comment")
	assert.Contains(t, result.Dockerfile, "# Another comment")
	// Syntax directive should be transformed, not preserved
	assert.NotContains(t, result.Dockerfile, "# syntax=codingbooth/boothfile")
	// Prologue should have docker syntax
	assert.Contains(t, result.Dockerfile, "# syntax=docker/dockerfile:1.7")
}

func TestCompiler_CompleteExample(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1

# Data engineering booth

# System dependencies
run apt-get update && apt-get install -y graphviz libpq-dev

# Languages
setup python 3.12
setup jdk 21 temurin

# Build tools
setup mvn 3.9.6

# Python packages
install pip django djangorestframework psycopg2-binary

# Project config
copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt

# Environment
env APP_ENV=production
`
	result := CompileString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)

	// Verify all expected instructions
	df := result.Dockerfile

	// Prologue
	assert.Contains(t, df, "# syntax=docker/dockerfile:1.7")
	assert.Contains(t, df, "FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}")

	// Commands
	assert.Contains(t, df, "RUN apt-get update && apt-get install -y graphviz libpq-dev")
	assert.Contains(t, df, "RUN python--setup.sh 3.12")
	assert.Contains(t, df, "RUN jdk--setup.sh 21 temurin")
	assert.Contains(t, df, "RUN mvn--setup.sh 3.9.6")
	assert.Contains(t, df, "RUN pip--install.sh django djangorestframework psycopg2-binary")
	assert.Contains(t, df, "COPY ./config /opt/config")
	assert.Contains(t, df, "COPY requirements.txt /tmp/requirements.txt")
	assert.Contains(t, df, "ENV APP_ENV=production")
}

func TestCompiler_OrderPreserved(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run echo first
run echo second
run echo third
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())

	df := result.Dockerfile
	firstIdx := strings.Index(df, "RUN echo first")
	secondIdx := strings.Index(df, "RUN echo second")
	thirdIdx := strings.Index(df, "RUN echo third")

	require.NotEqual(t, -1, firstIdx)
	require.NotEqual(t, -1, secondIdx)
	require.NotEqual(t, -1, thirdIdx)

	assert.Less(t, firstIdx, secondIdx, "first should come before second")
	assert.Less(t, secondIdx, thirdIdx, "second should come before third")
}

func TestCompiler_ArgVariableUsage(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
arg NODE_VERSION=20
arg PYTHON_VERSION=3.12

setup nodejs ${NODE_VERSION}
setup python ${PYTHON_VERSION}
`
	result := CompileString(content)

	assert.False(t, result.HasErrors())

	df := result.Dockerfile
	assert.Contains(t, df, "ARG NODE_VERSION=20")
	assert.Contains(t, df, "ARG PYTHON_VERSION=3.12")
	assert.Contains(t, df, "RUN nodejs--setup.sh ${NODE_VERSION}")
	assert.Contains(t, df, "RUN python--setup.sh ${PYTHON_VERSION}")
}

func TestCompiler_EmptyHeredoc(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run &&<<END

# only comments

END
`
	result := CompileString(content)

	// Empty heredoc (after stripping comments/blanks) should error
	assert.True(t, result.HasErrors())
	assert.Contains(t, result.Errors[0].Message, "empty after processing")
}

func TestCompiler_ValidationErrors(t *testing.T) {
	t.Run("run without args", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run
`
		result := CompileString(content)
		assert.True(t, result.HasErrors())
	})

	t.Run("copy without destination", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
copy ./source
`
		result := CompileString(content)
		assert.True(t, result.HasErrors())
	})

	t.Run("setup without tool", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup
`
		result := CompileString(content)
		assert.True(t, result.HasErrors())
	})

	t.Run("install without packages", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install pip
`
		result := CompileString(content)
		assert.True(t, result.HasErrors())
	})
}

func TestCompiler_ScriptValidation(t *testing.T) {
	t.Run("unknown setup script warns", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup pytohn 3.12
`
		parser := NewParser()
		parseResult := parser.ParseString(content)
		assert.False(t, parseResult.HasErrors())

		compiler := NewCompilerWithOptions(CompilerOptions{
			KnownSetupScripts: []string{"python", "nodejs", "go"},
		})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors(), "Should compile successfully")
		assert.True(t, result.HasWarnings(), "Should have warning for unknown script")
		assert.Len(t, result.Warnings, 1)
		assert.Contains(t, result.Warnings[0].Message, "Unknown setup script 'pytohn'")
		assert.Contains(t, result.Warnings[0].Hint, "python")
	})

	t.Run("unknown install script warns", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install ppi django
`
		parser := NewParser()
		parseResult := parser.ParseString(content)
		assert.False(t, parseResult.HasErrors())

		compiler := NewCompilerWithOptions(CompilerOptions{
			KnownInstallScripts: []string{"pip", "npm", "brew"},
		})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors(), "Should compile successfully")
		assert.True(t, result.HasWarnings(), "Should have warning for unknown script")
		assert.Contains(t, result.Warnings[0].Message, "Unknown install script 'ppi'")
		assert.Contains(t, result.Warnings[0].Hint, "pip")
	})

	t.Run("known setup script no warning", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup python 3.12
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{
			KnownSetupScripts: []string{"python", "nodejs", "go"},
		})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.False(t, result.HasWarnings(), "Should have no warnings for known script")
	})

	t.Run("custom setup script no warning", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup myapp
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{
			KnownSetupScripts:  []string{"python", "nodejs"},
			CustomSetupScripts: []string{"myapp"},
		})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.False(t, result.HasWarnings(), "Should have no warnings for custom script")
	})

	t.Run("no known scripts skips validation", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup unknownscript
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		// Compiler with no known scripts configured - should skip validation
		compiler := NewCompiler()
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.False(t, result.HasWarnings(), "Should have no warnings when validation disabled")
	})

	t.Run("multiple unknown scripts multiple warnings", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup pytohn
install ppi django
setup nodjes
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{
			KnownSetupScripts:   []string{"python", "nodejs"},
			KnownInstallScripts: []string{"pip", "npm"},
		})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.True(t, result.HasWarnings())
		assert.Len(t, result.Warnings, 3, "Should have 3 warnings")
	})
}

func TestCompiler_VariantProvidedSetups(t *testing.T) {
	t.Run("notebook variant skips setup notebook", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup notebook 18888
setup codeserver 19999
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{Variant: "notebook"})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.True(t, result.HasWarnings(), "Should warn about redundant setup")
		assert.Len(t, result.Warnings, 1, "Only notebook is redundant for notebook variant")
		assert.Contains(t, result.Warnings[0].Message, "setup 'notebook'")
		assert.Contains(t, result.Warnings[0].Message, "notebook")
		assert.Contains(t, result.Dockerfile, "# skipped: setup notebook 18888")
		assert.Contains(t, result.Dockerfile, "RUN codeserver--setup.sh 19999")
		assert.NotContains(t, result.Dockerfile, "RUN notebook--setup.sh")
	})

	t.Run("codeserver variant skips setup codeserver", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup notebook 18888
setup codeserver 19999
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{Variant: "codeserver"})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.Len(t, result.Warnings, 1)
		assert.Contains(t, result.Warnings[0].Message, "setup 'codeserver'")
		assert.Contains(t, result.Dockerfile, "# skipped: setup codeserver 19999")
		assert.Contains(t, result.Dockerfile, "RUN notebook--setup.sh 18888")
	})

	t.Run("no variant set means no skip", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup notebook 18888
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.False(t, result.HasWarnings())
		assert.Contains(t, result.Dockerfile, "RUN notebook--setup.sh 18888")
	})

	t.Run("unknown variant means no skip", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup notebook 18888
`
		parser := NewParser()
		parseResult := parser.ParseString(content)

		compiler := NewCompilerWithOptions(CompilerOptions{Variant: "desktop-xfce"})
		result := compiler.Compile(parseResult)

		assert.False(t, result.HasErrors())
		assert.False(t, result.HasWarnings())
		assert.Contains(t, result.Dockerfile, "RUN notebook--setup.sh 18888")
	})
}

func TestCompiler_SimilarityScore(t *testing.T) {
	t.Run("exact match high score", func(t *testing.T) {
		score := similarityScore("python", "python")
		assert.Greater(t, score, 10)
	})

	t.Run("similar strings have positive score", func(t *testing.T) {
		score := similarityScore("pytohn", "python")
		assert.Greater(t, score, 0)
	})

	t.Run("completely different low score", func(t *testing.T) {
		score := similarityScore("xyz", "abc")
		assert.Less(t, score, 2)
	})
}

func TestCompiler_SuggestScript(t *testing.T) {
	known := []string{"python", "nodejs", "go", "rust", "ruby"}

	t.Run("suggests similar script", func(t *testing.T) {
		suggestion := suggestScript("pytohn", known)
		assert.Equal(t, "python", suggestion)
	})

	t.Run("suggests nodejs for nodjes", func(t *testing.T) {
		suggestion := suggestScript("nodjes", known)
		assert.Equal(t, "nodejs", suggestion)
	})

	t.Run("no suggestion for completely different", func(t *testing.T) {
		suggestion := suggestScript("xyz", known)
		assert.Equal(t, "", suggestion)
	})
}

func TestScanSetupsDir(t *testing.T) {
	t.Run("empty string returns nil", func(t *testing.T) {
		setup, install := ScanSetupsDir("")
		assert.Nil(t, setup)
		assert.Nil(t, install)
	})

	t.Run("nonexistent dir returns nil", func(t *testing.T) {
		setup, install := ScanSetupsDir("/nonexistent/path")
		assert.Nil(t, setup)
		assert.Nil(t, install)
	})

	t.Run("scans real setups directory", func(t *testing.T) {
		// Try to find the actual setups directory
		dir := FindBuiltinSetupsDir()
		if dir == "" {
			t.Skip("Could not find built-in setups directory")
		}

		setup, install := ScanSetupsDir(dir)
		assert.NotEmpty(t, setup, "Should find setup scripts")
		assert.NotEmpty(t, install, "Should find install scripts")

		// Verify some known scripts exist
		assert.Contains(t, setup, "python")
		assert.Contains(t, install, "pip")
	})
}
