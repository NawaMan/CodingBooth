package appctx

import (
	"testing"

	"github.com/nawaman/workspace/cli/src/pkg/ilist"
	"github.com/nawaman/workspace/cli/src/pkg/nillable"
)

func TestAppContext_RoundTrip(t *testing.T) {
	builder := &AppContextBuilder{
		PrebuildRepo: "repo",
		WsVersion:    "1.0.0",
		Config: AppConfig{
			Dryrun:  nillable.NewNillableBool(true),
			Verbose: nillable.NewNillableBool(true),
			Image:   "test-image",
		},
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.CommonArgs.Append(ilist.NewList[string]("param1"))

	ctx := NewAppContext(builder)

	if ctx.PrebuildRepo() != "repo" {
		t.Fatalf("PrebuildRepo mismatch")
	}
	if !ctx.Dryrun() {
		t.Fatalf("Dryrun mismatch")
	}
	if ctx.Image() != "test-image" {
		t.Fatalf("Image mismatch")
	}

	got := ctx.CommonArgs().Slice()
	if len(got) != 1 || got[0].At(0) != "param1" {
		t.Fatalf("Expected CommonArgs ['param1'], got %v", got)
	}

	builder2 := ctx.ToBuilder()
	if builder2.PrebuildRepo != "repo" {
		t.Fatalf("builder2 PrebuildRepo mismatch")
	}

	got2 := builder2.CommonArgs.Slice()
	if len(got2) != 1 || got2[0].At(0) != "param1" {
		t.Fatalf("Expected builder2 CommonArgs ['param1'], got %v", got2)
	}

	// Stronger: rebuild ctx2 and compare
	ctx2 := NewAppContext(builder2)
	if ctx2.CommonArgs().At(0).At(0) != "param1" {
		t.Fatalf("Round-trip rebuild mismatch: %v", ctx2.CommonArgs().Slice())
	}
}

func TestAppContext_Immutability(t *testing.T) {
	builder := &AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.CommonArgs.Append(ilist.NewList[string]("initial"))

	ctx := NewAppContext(builder)

	// Modify original builder
	builder.CommonArgs.Append(ilist.NewList[string]("modified"))

	// Check context is unchanged
	if ctx.CommonArgs().Length() != 1 {
		t.Errorf("Context should still have 1 element, got %d", ctx.CommonArgs().Length())
	}

	// Modify new builder from context
	builder2 := ctx.ToBuilder()
	builder2.CommonArgs.Append(ilist.NewList[string]("modified2"))

	if ctx.CommonArgs().Length() != 1 {
		t.Errorf("Context should still have 1 element after builder2 mod, got %d", ctx.CommonArgs().Length())
	}
}

func TestAppContext_ConfigValues(t *testing.T) {
	builder := &AppContextBuilder{
		Config: AppConfig{
			Config:       nillable.NewNillableString("conf"),
			Workspace:    nillable.NewNillableString("path"),
			Dryrun:       nillable.NewNillableBool(true),
			Verbose:      nillable.NewNillableBool(true),
			Version:      nillable.NewNillableString("version"),
			KeepAlive:    true,
			SilenceBuild: true,
			Daemon:       true,
			Pull:         true,
			Dind:         true,
			Dockerfile:   "dockerfile",
			Image:        "image",
			Variant:      "variant",
			ProjectName:  "project",
			HostUID:      "uid",
			HostGID:      "gid",
			Timezone:     "tz",
			Name:         "container",
			Port:         "8080",
			EnvFile:      "env",
		},
	}

	ctx := NewAppContext(builder)

	if ctx.ConfigFile() != "conf" {
		t.Error("Config mismatch")
	}
	if ctx.Workspace() != "path" {
		t.Error("Workspace mismatch")
	}
	if !ctx.Dryrun() {
		t.Error("Dryrun mismatch")
	}
	if !ctx.Verbose() {
		t.Error("Verbose mismatch")
	}
	if !ctx.KeepAlive() {
		t.Error("Keepalive mismatch")
	}
	if !ctx.SilenceBuild() {
		t.Error("SilenceBuild mismatch")
	}
	if !ctx.Daemon() {
		t.Error("Daemon mismatch")
	}
	if !ctx.Pull() {
		t.Error("Pull mismatch")
	}
	if !ctx.Dind() {
		t.Error("Dind mismatch")
	}
	if ctx.Dockerfile() != "dockerfile" {
		t.Error("DockerFile mismatch")
	}
	if ctx.Image() != "image" {
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
	if ctx.Name() != "container" {
		t.Error("Name mismatch")
	}
	if ctx.Port() != "8080" {
		t.Error("Port mismatch")
	}
	if ctx.EnvFile() != "env" {
		t.Error("EnvFile mismatch")
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
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.CommonArgs.Append(ilist.NewList[string]("common"))
	builder.BuildArgs.Append(ilist.NewList[string]("build"))
	builder.RunArgs.Append(ilist.NewList[string]("run"))
	builder.Cmds.Append(ilist.NewList[string]("cmd"))

	ctx := NewAppContext(builder)

	if ctx.CommonArgs().At(0).At(0) != "common" {
		t.Error("CommonArgs mismatch")
	}
	if ctx.BuildArgs().At(0).At(0) != "build" {
		t.Error("BuildArgs mismatch")
	}
	if ctx.RunArgs().At(0).At(0) != "run" {
		t.Error("RunArgs mismatch")
	}
	if ctx.Cmds().At(0).At(0) != "cmd" {
		t.Error("Cmds mismatch")
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
}

func TestAppContext_ListSliceDetachment(t *testing.T) {
	b := &AppContextBuilder{CommonArgs: ilist.NewAppendableList[ilist.List[string]]()}
	b.CommonArgs.Append(ilist.NewList[string]("a"))
	ctx := NewAppContext(b)

	s := ctx.CommonArgs().Slice()
	s[0] = ilist.NewList[string]("mutated")

	if ctx.CommonArgs().At(0).At(0) != "a" {
		t.Fatalf("Expected context to remain 'a', got %q", ctx.CommonArgs().At(0))
	}
}
