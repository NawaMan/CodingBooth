// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParser_SyntaxDirective(t *testing.T) {
	t.Run("valid syntax directive", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors(), "should not have errors: %v", result.Errors)
		require.Len(t, result.Commands, 1)
		assert.Equal(t, CommandComment, result.Commands[0].Type)
	})

	t.Run("syntax directive with blank lines before", func(t *testing.T) {
		content := `

# syntax=codingbooth/boothfile:1
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors(), "should not have errors: %v", result.Errors)
		require.Len(t, result.Commands, 3)
		assert.Equal(t, CommandBlank, result.Commands[0].Type)
		assert.Equal(t, CommandBlank, result.Commands[1].Type)
		assert.Equal(t, CommandComment, result.Commands[2].Type)
	})

	t.Run("missing syntax directive", func(t *testing.T) {
		content := `run echo hello
`
		p := NewParser()
		result := p.ParseString(content)

		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Missing syntax directive")
	})

	t.Run("invalid syntax version", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:2
`
		p := NewParser()
		result := p.ParseString(content)

		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Invalid syntax directive")
	})
}

func TestParser_Comments(t *testing.T) {
	t.Run("full line comment", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
# This is a comment
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		require.Len(t, result.Commands, 2)
		assert.Equal(t, CommandComment, result.Commands[1].Type)
	})

	t.Run("inline comment", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run echo hello # this is inline
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		require.Len(t, result.Commands, 2)
		assert.Equal(t, CommandRun, result.Commands[1].Type)
		assert.Equal(t, []string{"echo", "hello"}, result.Commands[1].Args)
	})

	t.Run("hash in quoted string not treated as comment", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run echo "hello#world"
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		require.Len(t, result.Commands, 2)
		assert.Equal(t, CommandRun, result.Commands[1].Type)
		assert.Contains(t, result.Commands[1].Args, `"hello#world"`)
	})
}

func TestParser_BlankLines(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1

run echo hello

run echo world
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	blankCount := 0
	for _, cmd := range result.Commands {
		if cmd.Type == CommandBlank {
			blankCount++
		}
	}
	assert.Equal(t, 2, blankCount)
}

func TestParser_RunCommand(t *testing.T) {
	t.Run("simple run", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run apt-get update
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		require.Len(t, result.Commands, 2)
		cmd := result.Commands[1]
		assert.Equal(t, CommandRun, cmd.Type)
		assert.Equal(t, []string{"apt-get", "update"}, cmd.Args)
	})

	t.Run("run with && chain", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run apt-get update && apt-get install -y curl
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandRun, cmd.Type)
		assert.Contains(t, cmd.Args, "&&")
	})
}

func TestParser_HeredocVerbatim(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run <<END
apt-get update
apt-get install -y curl
END
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
	require.Len(t, result.Commands, 2)

	cmd := result.Commands[1]
	assert.Equal(t, CommandRunHeredoc, cmd.Type)
	assert.Equal(t, HeredocVerbatim, cmd.HeredocMode)
	assert.Equal(t, "END", cmd.HeredocDelimiter)
	assert.Equal(t, []string{"apt-get update", "apt-get install -y curl"}, cmd.HeredocContent)
}

func TestParser_HeredocAndJoin(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run &&<<EOF
apt-get update
apt-get install -y curl
rm -rf /var/lib/apt/lists/*
EOF
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	require.Len(t, result.Commands, 2)

	cmd := result.Commands[1]
	assert.Equal(t, CommandRunHeredoc, cmd.Type)
	assert.Equal(t, HeredocAndJoin, cmd.HeredocMode)
	assert.Equal(t, "EOF", cmd.HeredocDelimiter)
	assert.Len(t, cmd.HeredocContent, 3)
}

func TestParser_HeredocSemiJoin(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run ;<<DONE
rm -f /tmp/optional
echo "continuing"
DONE
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	require.Len(t, result.Commands, 2)

	cmd := result.Commands[1]
	assert.Equal(t, CommandRunHeredoc, cmd.Type)
	assert.Equal(t, HeredocSemiJoin, cmd.HeredocMode)
	assert.Equal(t, "DONE", cmd.HeredocDelimiter)
}

func TestParser_HeredocUnclosed(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run <<END
apt-get update
`
	p := NewParser()
	result := p.ParseString(content)

	assert.True(t, result.HasErrors())
	assert.Contains(t, result.Errors[0].Message, "Unclosed heredoc")
}

func TestParser_HeredocWithComment(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
run &&<<END # this comment should be ignored
apt-get update
END
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
	cmd := result.Commands[1]
	assert.Equal(t, CommandRunHeredoc, cmd.Type)
	assert.Equal(t, HeredocAndJoin, cmd.HeredocMode)
}

func TestParser_CopyCommand(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	require.Len(t, result.Commands, 3)

	cmd1 := result.Commands[1]
	assert.Equal(t, CommandCopy, cmd1.Type)
	assert.Equal(t, []string{"./config", "/opt/config"}, cmd1.Args)

	cmd2 := result.Commands[2]
	assert.Equal(t, CommandCopy, cmd2.Type)
	assert.Equal(t, []string{"requirements.txt", "/tmp/requirements.txt"}, cmd2.Args)
}

func TestParser_EnvCommand(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
env MY_VAR=value
env APP_ENV=production
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	require.Len(t, result.Commands, 3)

	cmd1 := result.Commands[1]
	assert.Equal(t, CommandEnv, cmd1.Type)
	assert.Equal(t, []string{"MY_VAR=value"}, cmd1.Args)
}

func TestParser_WorkdirCommand(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
workdir /app
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	cmd := result.Commands[1]
	assert.Equal(t, CommandWorkdir, cmd.Type)
	assert.Equal(t, []string{"/app"}, cmd.Args)
}

func TestParser_ExposeCommand(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
expose 8080
expose 3000 4000
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	cmd1 := result.Commands[1]
	assert.Equal(t, CommandExpose, cmd1.Type)
	assert.Equal(t, []string{"8080"}, cmd1.Args)

	cmd2 := result.Commands[2]
	assert.Equal(t, []string{"3000", "4000"}, cmd2.Args)
}

func TestParser_LabelCommand(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
label maintainer="team@example.com"
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	cmd := result.Commands[1]
	assert.Equal(t, CommandLabel, cmd.Type)
	assert.Equal(t, []string{`maintainer="team@example.com"`}, cmd.Args)
}

func TestParser_ArgCommand(t *testing.T) {
	t.Run("arg with default value", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
arg NODE_VERSION=20
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandArg, cmd.Type)
		assert.Equal(t, []string{"NODE_VERSION=20"}, cmd.Args)
	})

	t.Run("arg lowercase naming", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
arg node_version=20
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandArg, cmd.Type)
		assert.Equal(t, []string{"node_version=20"}, cmd.Args)
	})
}

func TestParser_SetupCommand(t *testing.T) {
	t.Run("setup without args", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup python
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandSetup, cmd.Type)
		assert.Equal(t, []string{"python"}, cmd.Args)
	})

	t.Run("setup with version", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup python 3.12
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandSetup, cmd.Type)
		assert.Equal(t, []string{"python", "3.12"}, cmd.Args)
	})

	t.Run("setup with multiple args", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setup jdk 21 temurin
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandSetup, cmd.Type)
		assert.Equal(t, []string{"jdk", "21", "temurin"}, cmd.Args)
	})
}

func TestParser_InstallCommand(t *testing.T) {
	t.Run("install single package", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install pip django
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandInstall, cmd.Type)
		assert.Equal(t, []string{"pip", "django"}, cmd.Args)
	})

	t.Run("install multiple packages", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
install pip django djangorestframework psycopg2-binary
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, CommandInstall, cmd.Type)
		assert.Equal(t, []string{"pip", "django", "djangorestframework", "psycopg2-binary"}, cmd.Args)
	})
}

func TestParser_DockerEscapeHatch(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
DOCKER HEALTHCHECK CMD curl -f http://localhost/ || exit 1
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	cmd := result.Commands[1]
	assert.Equal(t, CommandDocker, cmd.Type)
	assert.Equal(t, []string{"HEALTHCHECK CMD curl -f http://localhost/ || exit 1"}, cmd.Args)
}

func TestParser_UnknownCommand(t *testing.T) {
	t.Run("unknown command", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
unknown command
`
		p := NewParser()
		result := p.ParseString(content)

		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Unknown command: unknown")
	})

	t.Run("typo with suggestion", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
instal pip django
`
		p := NewParser()
		result := p.ParseString(content)

		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Unknown command: instal")
		assert.Contains(t, result.Errors[0].Hint, "install")
	})

	t.Run("typo setup", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
setpu python
`
		p := NewParser()
		result := p.ParseString(content)

		assert.True(t, result.HasErrors())
		assert.Contains(t, result.Errors[0].Message, "Unknown command: setpu")
		assert.Contains(t, result.Errors[0].Hint, "setup")
	})
}

func TestParser_CompleteExample(t *testing.T) {
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
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)

	// Count command types
	counts := make(map[CommandType]int)
	for _, cmd := range result.Commands {
		counts[cmd.Type]++
	}

	assert.Equal(t, 1, counts[CommandRun])
	assert.Equal(t, 3, counts[CommandSetup])
	assert.Equal(t, 1, counts[CommandInstall])
	assert.Equal(t, 2, counts[CommandCopy])
	assert.Equal(t, 1, counts[CommandEnv])
}

func TestParser_LineNumbers(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1

run echo hello

setup python
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	require.Len(t, result.Commands, 5)

	assert.Equal(t, 1, result.Commands[0].LineNumber) // syntax
	assert.Equal(t, 2, result.Commands[1].LineNumber) // blank
	assert.Equal(t, 3, result.Commands[2].LineNumber) // run
	assert.Equal(t, 4, result.Commands[3].LineNumber) // blank
	assert.Equal(t, 5, result.Commands[4].LineNumber) // setup
}

func TestParser_QuotedArguments(t *testing.T) {
	t.Run("double quotes", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
label maintainer="John Doe <john@example.com>"
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Equal(t, []string{`maintainer="John Doe <john@example.com>"`}, cmd.Args)
	})

	t.Run("single quotes", func(t *testing.T) {
		content := `# syntax=codingbooth/boothfile:1
run echo 'hello world'
`
		p := NewParser()
		result := p.ParseString(content)

		assert.False(t, result.HasErrors())
		cmd := result.Commands[1]
		assert.Contains(t, cmd.Args, "'hello world'")
	})
}

func TestParser_MinimalBoothfile(t *testing.T) {
	content := `# syntax=codingbooth/boothfile:1
`
	p := NewParser()
	result := p.ParseString(content)

	assert.False(t, result.HasErrors())
	assert.Len(t, result.Commands, 1)
	assert.Equal(t, CommandComment, result.Commands[0].Type)
}
