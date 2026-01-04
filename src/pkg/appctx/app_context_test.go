package appctx

import (
	"testing"

	"github.com/nawaman/workspace/src/pkg/ilist"
)

func TestAppContext_RoundTrip(t *testing.T) {
	builder := &AppContextBuilder{
		PrebuildRepo: "repo",
		WsVersion:    "1.0.0",
		Config: AppConfig{
			Dryrun:    true,
			Verbose:   true,
			ImageName: "test-image",
		},
		CommonArgs: ilist.NewAppendableList[string](),
	}
	builder.CommonArgs.Append("param1")

	ctx := NewAppContext(builder)

	if ctx.PrebuildRepo() != "repo" {
		t.Fatalf("PrebuildRepo mismatch")
	}
	if !ctx.Dryrun() {
		t.Fatalf("Dryrun mismatch")
	}
	if ctx.ImageName() != "test-image" {
		t.Fatalf("ImageName mismatch")
	}

	got := ctx.CommonArgs().Slice()
	if len(got) != 1 || got[0] != "param1" {
		t.Fatalf("Expected CommonArgs ['param1'], got %v", got)
	}

	builder2 := ctx.ToBuilder()
	if builder2.PrebuildRepo != "repo" {
		t.Fatalf("builder2 PrebuildRepo mismatch")
	}

	got2 := builder2.CommonArgs.Slice()
	if len(got2) != 1 || got2[0] != "param1" {
		t.Fatalf("Expected builder2 CommonArgs ['param1'], got %v", got2)
	}

	// Stronger: rebuild ctx2 and compare
	ctx2 := NewAppContext(builder2)
	if ctx2.CommonArgs().At(0) != "param1" {
		t.Fatalf("Round-trip rebuild mismatch: %v", ctx2.CommonArgs().Slice())
	}
}

func TestAppContext_Immutability(t *testing.T) {
	builder := &AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[string](),
	}
	builder.CommonArgs.Append("initial")

	ctx := NewAppContext(builder)

	// Modify original builder
	builder.CommonArgs.Append("modified")

	// Check context is unchanged
	if ctx.CommonArgs().Length() != 1 {
		t.Errorf("Context should still have 1 element, got %d", ctx.CommonArgs().Length())
	}

	// Modify new builder from context
	builder2 := ctx.ToBuilder()
	builder2.CommonArgs.Append("modified2")

	if ctx.CommonArgs().Length() != 1 {
		t.Errorf("Context should still have 1 element after builder2 mod, got %d", ctx.CommonArgs().Length())
	}
}

func TestAppContext_ConfigValues(t *testing.T) {
	builder := &AppContextBuilder{
		Config: AppConfig{
			ConfigFile:       "conf",
			WorkspacePath:    "path",
			Dryrun:           true,
			Verbose:          true,
			Keepalive:        true,
			SilenceBuild:     true,
			Daemon:           true,
			DoPull:           true,
			Dind:             true,
			DockerFile:       "dockerfile",
			ImageName:        "image",
			Variant:          "variant",
			Version:          "version",
			ProjectName:      "project",
			HostUID:          "uid",
			HostGID:          "gid",
			Timezone:         "tz",
			ContainerName:    "container",
			WorkspacePort:    "8080",
			HostPort:         "9090",
			ContainerEnvFile: "env",
			DindNet:          "net",
			DindName:         "dind",
			DockerBin:        "docker",
		},
	}

	ctx := NewAppContext(builder)

	if ctx.ConfigFile() != "conf" {
		t.Error("ConfigFile mismatch")
	}
	if ctx.WorkspacePath() != "path" {
		t.Error("WorkspacePath mismatch")
	}
	if !ctx.Dryrun() {
		t.Error("Dryrun mismatch")
	}
	if !ctx.Verbose() {
		t.Error("Verbose mismatch")
	}
	if !ctx.Keepalive() {
		t.Error("Keepalive mismatch")
	}
	if !ctx.SilenceBuild() {
		t.Error("SilenceBuild mismatch")
	}
	if !ctx.Daemon() {
		t.Error("Daemon mismatch")
	}
	if !ctx.DoPull() {
		t.Error("DoPull mismatch")
	}
	if !ctx.Dind() {
		t.Error("Dind mismatch")
	}
	if ctx.DockerFile() != "dockerfile" {
		t.Error("DockerFile mismatch")
	}
	if ctx.ImageName() != "image" {
		t.Error("ImageName mismatch")
	}
	if ctx.Variant() != "variant" {
		t.Error("Variant mismatch")
	}
	if ctx.Version() != "version" {
		t.Error("Version mismatch")
	}
	if ctx.ProjectName() != "project" {
		t.Error("ProjectName mismatch")
	}
	if ctx.HostUID() != "uid" {
		t.Error("HostUID mismatch")
	}
	if ctx.HostGID() != "gid" {
		t.Error("HostGID mismatch")
	}
	if ctx.Timezone() != "tz" {
		t.Error("Timezone mismatch")
	}
	if ctx.ContainerName() != "container" {
		t.Error("ContainerName mismatch")
	}
	if ctx.WorkspacePort() != "8080" {
		t.Error("WorkspacePort mismatch")
	}
	if ctx.HostPort() != "9090" {
		t.Error("HostPort mismatch")
	}
	if ctx.ContainerEnvFile() != "env" {
		t.Error("ContainerEnvFile mismatch")
	}
	if ctx.DindNet() != "net" {
		t.Error("DindNet mismatch")
	}
	if ctx.DindName() != "dind" {
		t.Error("DindName mismatch")
	}
	if ctx.DockerBin() != "docker" {
		t.Error("DockerBin mismatch")
	}
}

func TestAppContext_DerivedValues(t *testing.T) {
	builder := &AppContextBuilder{
		PrebuildRepo:   "repo",
		WsVersion:      "v1",
		SetupsDir:      "dir",
		ScriptName:     "script",
		ScriptDir:      "sdir",
		LibDir:         "ldir",
		HasNotebook:    true,
		HasVscode:      true,
		HasDesktop:     true,
		CreatedDindNet: true,
		RunMode:        "run",
		LocalBuild:     true,
		ImageMode:      "img",
		PortGenerated:  true,
	}

	ctx := NewAppContext(builder)

	if ctx.PrebuildRepo() != "repo" {
		t.Error("PrebuildRepo mismatch")
	}
	if ctx.WsVersion() != "v1" {
		t.Error("WsVersion mismatch")
	}
	if ctx.SetupsDir() != "dir" {
		t.Error("SetupsDir mismatch")
	}
	if ctx.ScriptName() != "script" {
		t.Error("ScriptName mismatch")
	}
	if ctx.ScriptDir() != "sdir" {
		t.Error("ScriptDir mismatch")
	}
	if ctx.LibDir() != "ldir" {
		t.Error("LibDir mismatch")
	}
	if !ctx.HasNotebook() {
		t.Error("HasNotebook mismatch")
	}
	if !ctx.HasVscode() {
		t.Error("HasVscode mismatch")
	}
	if !ctx.HasDesktop() {
		t.Error("HasDesktop mismatch")
	}
	if !ctx.CreatedDindNet() {
		t.Error("CreatedDindNet mismatch")
	}
	if ctx.RunMode() != "run" {
		t.Error("RunMode mismatch")
	}
	if !ctx.LocalBuild() {
		t.Error("LocalBuild mismatch")
	}
	if ctx.ImageMode() != "img" {
		t.Error("ImageMode mismatch")
	}
	if !ctx.PortGenerated() {
		t.Error("PortGenerated mismatch")
	}
}

func TestAppContext_Lists(t *testing.T) {
	builder := &AppContextBuilder{
		CommonArgs:    ilist.NewAppendableList[string](),
		BuildArgs:     ilist.NewAppendableList[string](),
		RunArgs:       ilist.NewAppendableList[string](),
		Cmds:          ilist.NewAppendableList[string](),
		KeepaliveArgs: ilist.NewAppendableList[string](),
		TtyArgs:       ilist.NewAppendableList[string](),
	}
	builder.CommonArgs.Append("common")
	builder.BuildArgs.Append("build")
	builder.RunArgs.Append("run")
	builder.Cmds.Append("cmd")
	builder.KeepaliveArgs.Append("keepalive")
	builder.TtyArgs.Append("tty")

	ctx := NewAppContext(builder)

	if ctx.CommonArgs().At(0) != "common" {
		t.Error("CommonArgs mismatch")
	}
	if ctx.BuildArgs().At(0) != "build" {
		t.Error("BuildArgs mismatch")
	}
	if ctx.RunArgs().At(0) != "run" {
		t.Error("RunArgs mismatch")
	}
	if ctx.Cmds().At(0) != "cmd" {
		t.Error("Cmds mismatch")
	}
	if ctx.KeepaliveArgs().At(0) != "keepalive" {
		t.Error("KeepaliveArgs mismatch")
	}
	if ctx.TtyArgs().At(0) != "tty" {
		t.Error("TtyArgs mismatch")
	}
}

func TestAppContextBuilder_NilListsSafeguard(t *testing.T) {
	ctx := NewAppContext(&AppContextBuilder{})

	if ctx.CommonArgs().Length() != 0 {
		t.Fatal("CommonArgs should be empty")
	}
	if ctx.BuildArgs().Length() != 0 {
		t.Fatal("BuildArgs should be empty")
	}
	if ctx.RunArgs().Length() != 0 {
		t.Fatal("RunArgs should be empty")
	}
	if ctx.Cmds().Length() != 0 {
		t.Fatal("Cmds should be empty")
	}
	if ctx.KeepaliveArgs().Length() != 0 {
		t.Fatal("KeepaliveArgs should be empty")
	}
	if ctx.TtyArgs().Length() != 0 {
		t.Fatal("TtyArgs should be empty")
	}

	b2 := ctx.ToBuilder()
	if b2.CommonArgs.Length() != 0 {
		t.Fatal("b2 CommonArgs should be empty")
	}
	if b2.BuildArgs.Length() != 0 {
		t.Fatal("b2 BuildArgs should be empty")
	}
	if b2.RunArgs.Length() != 0 {
		t.Fatal("b2 RunArgs should be empty")
	}
	if b2.Cmds.Length() != 0 {
		t.Fatal("b2 Cmds should be empty")
	}
	if b2.KeepaliveArgs.Length() != 0 {
		t.Fatal("b2 KeepaliveArgs should be empty")
	}
	if b2.TtyArgs.Length() != 0 {
		t.Fatal("b2 TtyArgs should be empty")
	}
}

func TestAppContext_ListSliceDetachment(t *testing.T) {
	b := &AppContextBuilder{CommonArgs: ilist.NewAppendableList[string]()}
	b.CommonArgs.Append("a")
	ctx := NewAppContext(b)

	s := ctx.CommonArgs().Slice()
	s[0] = "mutated"

	if ctx.CommonArgs().At(0) != "a" {
		t.Fatalf("Expected context to remain 'a', got %q", ctx.CommonArgs().At(0))
	}
}
