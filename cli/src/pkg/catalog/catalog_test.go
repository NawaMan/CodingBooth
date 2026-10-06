// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package catalog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScriptVersion(t *testing.T) {
	cases := map[string]string{
		"#!/bin/bash\n# Copyright\n# cb-version: 1.2.3\n":   "1.2.3",
		"// header\n// cb-version: 0.1.0\n":                 "0.1.0",
		"<!-- title -->\n<!-- cb-version: 2.0.0 -->\n<p>\n": "2.0.0",
		"#!/bin/bash\necho hi\n":                            "",
	}
	for in, want := range cases {
		if got := ScriptVersion([]byte(in)); got != want {
			t.Errorf("ScriptVersion(%q) = %q, want %q", in, got, want)
		}
	}
	// Past the header window, a mention is not a declaration.
	late := strings.Repeat("echo\n", scriptHeaderLines) + "# cb-version: 9.9.9\n"
	if got := ScriptVersion([]byte(late)); got != "" {
		t.Errorf("late cb-version picked up: %q", got)
	}
}

func TestTOMLVersionAndParams(t *testing.T) {
	data := []byte(`cb-version = "1.4.0"
display-name = "Java"

[params.JDK_VERSION]
default = "25"

[params.JDK_VENDOR]
default = "temurin"
`)
	v, err := TOMLVersion(data)
	if err != nil || v != "1.4.0" {
		t.Fatalf("TOMLVersion = %q, %v", v, err)
	}
	p, err := TOMLParams(data)
	if err != nil || strings.Join(p, ",") != "JDK_VERSION,JDK_VENDOR" {
		t.Fatalf("TOMLParams = %v, %v (declaration order matters)", p, err)
	}
}

func TestSemver(t *testing.T) {
	for _, bad := range []string{"", "1", "1.2", "v1.2.3", "1.2.3-rc1", "01.2.3"} {
		if _, err := ParseSemver(bad); err == nil {
			t.Errorf("ParseSemver(%q) accepted", bad)
		}
	}
	v := func(s string) Semver { x, _ := ParseSemver(s); return x }
	if v("1.10.0").Compare(v("1.9.9")) != 1 || v("1.0.0").Compare(v("1.0.0")) != 0 {
		t.Error("Compare is not numeric")
	}
	breaking := []struct {
		from, to string
		want     bool
	}{
		{"1.0.0", "2.0.0", true},
		{"1.0.0", "1.1.0", false},
		{"0.1.0", "0.2.0", true}, // 0.x: a new minor is breaking
		{"0.1.0", "0.1.1", false},
		{"0.3.0", "1.0.0", true},
	}
	for _, c := range breaking {
		if got := v(c.from).Breaking(v(c.to)); got != c.want {
			t.Errorf("%s → %s breaking = %v, want %v", c.from, c.to, got, c.want)
		}
	}
}

func item(kind, name, ver, sum string) Item {
	return Item{Kind: kind, Name: name, Version: ver, SHA256: sum, Path: name}
}

func findingFor(fs []Finding, name string) *Finding {
	for i := range fs {
		if fs[i].Item.Name == name {
			return &fs[i]
		}
	}
	return nil
}

func TestCheck(t *testing.T) {
	base := []Item{
		item(KindSetup, "unchanged", "1.0.0", "aaa"),
		item(KindSetup, "changed-no-bump", "1.0.0", "aaa"),
		item(KindSetup, "changed-bumped", "1.0.0", "aaa"),
		item(KindSetup, "bump-no-change", "1.0.0", "aaa"),
		item(KindSetup, "went-down", "1.2.0", "aaa"),
		item(KindSetup, "removed", "1.0.0", "aaa"),
	}
	cur := []Item{
		item(KindSetup, "unchanged", "1.0.0", "aaa"),
		item(KindSetup, "changed-no-bump", "1.0.0", "bbb"),
		item(KindSetup, "changed-bumped", "1.0.1", "bbb"),
		item(KindSetup, "bump-no-change", "1.1.0", "aaa"),
		item(KindSetup, "went-down", "1.1.0", "bbb"),
		item(KindSetup, "new", "0.1.0", "ccc"),
		item(KindSetup, "no-version", "", "ddd"),
		item(KindSetup, "bad-version", "v2", "eee"),
	}
	fs := Check(base, cur, nil, nil)

	want := map[string]Level{
		"changed-no-bump": Fail,
		"changed-bumped":  Info,
		"bump-no-change":  Warn,
		"went-down":       Fail,
		"removed":         Info,
		"new":             Info,
		"no-version":      Fail,
		"bad-version":     Fail,
	}
	for name, level := range want {
		f := findingFor(fs, name)
		if f == nil || f.Level != level {
			t.Errorf("%s: got %+v, want %s", name, f, level)
		}
	}
	if f := findingFor(fs, "unchanged"); f != nil {
		t.Errorf("unchanged item reported: %+v", f)
	}
	if !HasFail(fs) {
		t.Error("HasFail = false")
	}
}

func TestCheckNoBaselineOnlyValidates(t *testing.T) {
	cur := []Item{item(KindSetup, "ok", "1.0.0", "a"), item(KindSetup, "missing", "", "b")}
	fs := Check(nil, cur, nil, nil)
	if len(fs) != 1 || fs[0].Item.Name != "missing" || fs[0].Level != Fail {
		t.Fatalf("got %+v", fs)
	}
}

func TestCheckParamContract(t *testing.T) {
	params := map[string][]string{}
	lookup := func(prefix string) ParamLookup {
		return func(it Item) ([]string, bool) { p, ok := params[prefix+it.Name]; return p, ok }
	}
	base := []Item{
		item(KindTemplate, "appended", "1.0.0", "a"),
		item(KindTemplate, "reordered-minor", "1.0.0", "a"),
		item(KindTemplate, "reordered-major", "1.0.0", "a"),
		item(KindExtension, "x+removed-zero", "0.1.0", "a"),
	}
	cur := []Item{
		item(KindTemplate, "appended", "1.1.0", "b"),
		item(KindTemplate, "reordered-minor", "1.1.0", "b"),
		item(KindTemplate, "reordered-major", "2.0.0", "b"),
		item(KindExtension, "x+removed-zero", "0.1.1", "b"),
	}
	params["base:appended"], params["cur:appended"] = []string{"A"}, []string{"A", "B"}
	params["base:reordered-minor"], params["cur:reordered-minor"] = []string{"A", "B"}, []string{"B", "A"}
	params["base:reordered-major"], params["cur:reordered-major"] = []string{"A", "B"}, []string{"B", "A"}
	params["base:x+removed-zero"], params["cur:x+removed-zero"] = []string{"A", "B"}, []string{"A"}

	fs := Check(base, cur, lookup("base:"), lookup("cur:"))
	want := map[string]Level{
		"appended":        Info,
		"reordered-minor": Fail,
		"reordered-major": Info,
		"x+removed-zero":  Fail, // 0.x needs a new minor, not a patch
	}
	for name, level := range want {
		if f := findingFor(fs, name); f == nil || f.Level != level {
			t.Errorf("%s: got %+v, want %s", name, f, level)
		}
	}
}

func TestFormatParseRoundTrip(t *testing.T) {
	items := []Item{item(KindSetup, "go", "1.0.0", "abc"), item(KindExtension, "go+linter", "0.1.0", "def")}
	got, err := Parse(Format(items))
	if err != nil || len(got) != 2 || got[1] != items[1] {
		t.Fatalf("round trip: %+v, %v", got, err)
	}
}

func write(t *testing.T, root, rel, content string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCollect(t *testing.T) {
	root := t.TempDir()
	write(t, root, SetupsDir+"/go--setup.sh", "#!/bin/bash\n# cb-version: 1.0.0\n")
	write(t, root, SetupsDir+"/npm--install.sh", "#!/bin/bash\n# cb-version: 1.0.0\n")
	write(t, root, SetupsDir+"/cb-has-vscode.sh", "#!/bin/bash\n# cb-version: 1.0.0\n")
	write(t, root, SetupsDir+"/libs/skip-setup.sh", "# cb-version: 1.0.0\n")
	write(t, root, SetupsDir+"/future/ocaml--setup.sh", "#!/bin/bash\n")
	write(t, root, SetupsDir+"/logo-files/index.html", "<p>")
	write(t, root, SetupsDir+"/logo-files/"+AssetsVersionFile, "0.1.0\n")
	write(t, root, TemplatesDir+"/languages/meta.toml", "display-name = \"Languages\"\n")
	write(t, root, TemplatesDir+"/languages/go/template.toml", "cb-version = \"1.0.0\"\n")
	write(t, root, TemplatesDir+"/languages/go/linter--extension.toml", "cb-version = \"0.1.0\"\n")

	items, err := Collect(root)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, it := range items {
		got = append(got, it.Kind+":"+it.Name+"@"+it.Version)
	}
	want := "setup:go@1.0.0 install:npm@1.0.0 helper:cb-has-vscode.sh@1.0.0 lib:skip-setup.sh@1.0.0 " +
		"assets:logo-files@0.1.0 template:go@1.0.0 extension:go+linter@0.1.0"
	if strings.Join(got, " ") != want {
		t.Errorf("Collect:\n got  %s\n want %s", strings.Join(got, " "), want)
	}

	// The template's hash must not move when only an extension changes.
	tmplHash := items[5].SHA256
	write(t, root, TemplatesDir+"/languages/go/linter--extension.toml", "cb-version = \"0.1.1\"\n")
	items, _ = Collect(root)
	if items[5].SHA256 != tmplHash {
		t.Error("editing an extension changed its parent template's hash")
	}
	// But a non-extension file in the template directory is part of the template.
	write(t, root, TemplatesDir+"/languages/go/home-seed/.goenv", "x")
	items, _ = Collect(root)
	if items[5].SHA256 == tmplHash {
		t.Error("a home-seed file did not change the template's hash")
	}
}
