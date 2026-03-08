// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWriteOutput_CreatesBoothDir(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	info, err := os.Stat(filepath.Join(tmpDir, ".booth"))
	require.NoError(t, err)
	assert.True(t, info.IsDir())
}

func TestWriteOutput_AllowsExistingBoothDir(t *testing.T) {
	tmpDir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(tmpDir, ".booth"), 0755))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	// Verify file was written
	data, err := os.ReadFile(filepath.Join(tmpDir, ".booth", "config.toml"))
	require.NoError(t, err)
	assert.Contains(t, string(data), `variant = "base"`)
}

func TestWriteOutput_OverwritesExistingFiles(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))

	// Write an existing config.toml
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte("old content"), 0644))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "codeserver"},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(boothDir, "config.toml"))
	require.NoError(t, err)
	assert.Contains(t, string(data), `variant = "codeserver"`)
	assert.NotContains(t, string(data), "old content")
}

func TestOutputPaths_Basic(t *testing.T) {
	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	paths := OutputPaths(out, "/tmp/proj")
	assert.Contains(t, paths, "/tmp/proj/.booth/.gitignore")
	assert.Contains(t, paths, "/tmp/proj/.booth/config.toml")
	assert.Len(t, paths, 2)
}

func TestOutputPaths_Full(t *testing.T) {
	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "codeserver"},
		Boothfile: &BoothfileContent{Content: "setup go 1.24\n"},
		Startups:  []FileContent{{RelPath: "50-myapp--startup.sh", Content: "echo hello\n"}},
		Setups:    []FileContent{{RelPath: "myapp--setup.sh"}},
		Home:      []FileContent{{RelPath: ".bashrc"}},
		HomeSeed:  []FileContent{{RelPath: ".config/myapp/config.yaml"}},
	}
	paths := OutputPaths(out, "/tmp/proj")
	assert.Contains(t, paths, "/tmp/proj/.booth/.gitignore")
	assert.Contains(t, paths, "/tmp/proj/.booth/config.toml")
	assert.Contains(t, paths, "/tmp/proj/.booth/Boothfile")
	assert.Contains(t, paths, "/tmp/proj/.booth/startups/50-myapp--startup.sh")
	assert.Contains(t, paths, "/tmp/proj/.booth/setups/myapp--setup.sh")
	assert.Contains(t, paths, "/tmp/proj/.booth/home/.bashrc")
	assert.Contains(t, paths, "/tmp/proj/.booth/home-seed/.config/myapp/config.yaml")
	assert.Len(t, paths, 7)
}

func TestOutputPaths_SkipsNilFields(t *testing.T) {
	out := &BoothOutput{}
	paths := OutputPaths(out, "/tmp/proj")
	// Only .gitignore
	assert.Equal(t, []string{"/tmp/proj/.booth/.gitignore"}, paths)
}

func TestFindConflicts_NoConflicts(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	conflicts := FindConflicts(out, tmpDir)
	assert.Nil(t, conflicts)
}

func TestFindConflicts_WithConflicts(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte("old"), 0644))

	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go\n"},
	}
	conflicts := FindConflicts(out, tmpDir)
	assert.Len(t, conflicts, 1)
	assert.Contains(t, conflicts[0], "config.toml")
}

func TestFindConflicts_EmptyBoothDir(t *testing.T) {
	tmpDir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(tmpDir, ".booth"), 0755))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	conflicts := FindConflicts(out, tmpDir)
	assert.Nil(t, conflicts)
}

func TestWriteOutput_WritesConfigToml(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config: &ConfigToml{
			Variant: "codeserver",
			Port:    "NEXT",
		},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(tmpDir, ".booth", "config.toml"))
	require.NoError(t, err)
	content := string(data)
	assert.Contains(t, content, `variant = "codeserver"`)
	assert.Contains(t, content, `port = "NEXT"`)
}

func TestWriteOutput_WritesBoothfile(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go 1.24\n"},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(tmpDir, ".booth", "Boothfile"))
	require.NoError(t, err)
	content := string(data)
	assert.Contains(t, content, "# syntax=codingbooth/boothfile:1")
	assert.Contains(t, content, "setup go 1.24")
}

func TestWriteOutput_WritesStartups(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config:   &ConfigToml{Variant: "base"},
		Startups: []FileContent{{RelPath: "50-test--startup.sh", Content: "echo hello\n"}},
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	path := filepath.Join(tmpDir, ".booth", "startups", "50-test--startup.sh")
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	content := string(data)
	assert.Contains(t, content, "#!/bin/bash")
	assert.Contains(t, content, "echo hello")

	// Verify executable permission
	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.True(t, info.Mode()&0100 != 0, "startup file should be executable")
}

func TestWriteOutput_SkipsNilFields(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
		// Boothfile, Startups, Home, HomeSeed, Setups all nil/empty
	}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	// config.toml should exist
	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "config.toml"))
	assert.NoError(t, err)

	// Others should not exist
	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "Boothfile"))
	assert.True(t, os.IsNotExist(err))

	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "startups"))
	assert.True(t, os.IsNotExist(err))

	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "setups"))
	assert.True(t, os.IsNotExist(err))

	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "home"))
	assert.True(t, os.IsNotExist(err))

	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "home-seed"))
	assert.True(t, os.IsNotExist(err))
}

func TestWriteOutput_CopiesSetupFiles(t *testing.T) {
	srcDir := t.TempDir()
	targetDir := t.TempDir()

	// Create a source setup script
	setupSrc := filepath.Join(srcDir, "myapp--setup.sh")
	require.NoError(t, os.WriteFile(setupSrc, []byte("#!/bin/bash\napt-get install myapp\n"), 0755))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
		Setups: []FileContent{
			{SourcePath: setupSrc, RelPath: "myapp--setup.sh"},
		},
	}
	err := WriteOutput(out, targetDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(targetDir, ".booth", "setups", "myapp--setup.sh"))
	require.NoError(t, err)
	assert.Contains(t, string(data), "apt-get install myapp")
}

func TestWriteOutput_CopiesHomeFiles(t *testing.T) {
	srcDir := t.TempDir()
	targetDir := t.TempDir()

	// Create a source home file
	homeSrc := filepath.Join(srcDir, ".bashrc")
	require.NoError(t, os.WriteFile(homeSrc, []byte("export PATH=$PATH:/opt/bin\n"), 0644))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
		Home: []FileContent{
			{SourcePath: homeSrc, RelPath: ".bashrc"},
		},
	}
	err := WriteOutput(out, targetDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(targetDir, ".booth", "home", ".bashrc"))
	require.NoError(t, err)
	assert.Contains(t, string(data), "export PATH")
}

func TestWriteOutput_CopiesHomeSeedFiles(t *testing.T) {
	srcDir := t.TempDir()
	targetDir := t.TempDir()

	// Create a source home-seed file
	seedSrc := filepath.Join(srcDir, "config.yaml")
	require.NoError(t, os.WriteFile(seedSrc, []byte("setting: default\n"), 0644))

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
		HomeSeed: []FileContent{
			{SourcePath: seedSrc, RelPath: ".config/myapp/config.yaml"},
		},
	}
	err := WriteOutput(out, targetDir)
	require.NoError(t, err)

	data, err := os.ReadFile(filepath.Join(targetDir, ".booth", "home-seed", ".config", "myapp", "config.yaml"))
	require.NoError(t, err)
	assert.Contains(t, string(data), "setting: default")
}

func TestWriteOutput_FullOutput(t *testing.T) {
	srcDir := t.TempDir()
	targetDir := t.TempDir()

	// Create source files
	setupSrc := filepath.Join(srcDir, "django--setup.sh")
	require.NoError(t, os.WriteFile(setupSrc, []byte("pip install django\n"), 0755))

	homeSrc := filepath.Join(srcDir, ".gitconfig")
	require.NoError(t, os.WriteFile(homeSrc, []byte("[user]\nname = Test\n"), 0644))

	seedSrc := filepath.Join(srcDir, "nvim.lua")
	require.NoError(t, os.WriteFile(seedSrc, []byte("-- neovim config\n"), 0644))

	out := &BoothOutput{
		Config: &ConfigToml{
			Variant:  "codeserver",
			Port:     "NEXT",
			Timezone: "America/Toronto",
			Dind:     true,
			RunArgs:  []string{"-e", "TZ=America/Toronto"},
		},
		Boothfile: &BoothfileContent{
			Content: "setup python 3.12\nsetup jdk 21 temurin\ninstall pip django\n",
		},
		Startups: []FileContent{
			{RelPath: "50-myapp--startup.sh", Content: "/opt/myapp/migrate.sh\n"},
		},
		Setups: []FileContent{
			{SourcePath: setupSrc, RelPath: "django--setup.sh"},
		},
		Home: []FileContent{
			{SourcePath: homeSrc, RelPath: ".gitconfig"},
		},
		HomeSeed: []FileContent{
			{SourcePath: seedSrc, RelPath: ".config/nvim/init.lua"},
		},
	}

	err := WriteOutput(out, targetDir)
	require.NoError(t, err)

	boothDir := filepath.Join(targetDir, ".booth")

	// Verify all files exist
	assert.FileExists(t, filepath.Join(boothDir, "config.toml"))
	assert.FileExists(t, filepath.Join(boothDir, "Boothfile"))
	assert.FileExists(t, filepath.Join(boothDir, "startups", "50-myapp--startup.sh"))
	assert.FileExists(t, filepath.Join(boothDir, "setups", "django--setup.sh"))
	assert.FileExists(t, filepath.Join(boothDir, "home", ".gitconfig"))
	assert.FileExists(t, filepath.Join(boothDir, "home-seed", ".config", "nvim", "init.lua"))

	// Verify config content
	configData, _ := os.ReadFile(filepath.Join(boothDir, "config.toml"))
	assert.Contains(t, string(configData), `variant = "codeserver"`)
	assert.Contains(t, string(configData), "dind = true")

	// Verify boothfile content
	bfData, _ := os.ReadFile(filepath.Join(boothDir, "Boothfile"))
	assert.Contains(t, string(bfData), "# syntax=codingbooth/boothfile:1")
	assert.Contains(t, string(bfData), "setup python 3.12")

	// Verify startup content
	startupData, _ := os.ReadFile(filepath.Join(boothDir, "startups", "50-myapp--startup.sh"))
	assert.Contains(t, string(startupData), "#!/bin/bash")
	assert.Contains(t, string(startupData), "/opt/myapp/migrate.sh")
}

func TestWriteOutput_TargetDirCreatedIfMissing(t *testing.T) {
	tmpDir := t.TempDir()
	targetDir := filepath.Join(tmpDir, "new-project")

	out := &BoothOutput{
		Config: &ConfigToml{Variant: "base"},
	}
	err := WriteOutput(out, targetDir)
	require.NoError(t, err)

	assert.DirExists(t, filepath.Join(targetDir, ".booth"))
}

func TestWriteOutput_NilConfig(t *testing.T) {
	tmpDir := t.TempDir()
	out := &BoothOutput{}
	err := WriteOutput(out, tmpDir)
	require.NoError(t, err)

	// .booth dir should exist but be empty of generated files
	assert.DirExists(t, filepath.Join(tmpDir, ".booth"))
	_, err = os.Stat(filepath.Join(tmpDir, ".booth", "config.toml"))
	assert.True(t, os.IsNotExist(err))
}
