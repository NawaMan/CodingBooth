// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// `booth config repair --into <name>` handles the edits repair alone cannot read
// back because no booth config flag writes them: an added `install apt …`, a
// `run …`, a `setup …` with its `arg`, a run-args entry with no flag (`--gpus all`).
// It moves those lines into a project template, .booth/templates/<name>.toml —
// each run of Boothfile lines as a segment in the order band it sat in, with the
// comments directly above it; each added `arg NAME=VALUE` as a param; each
// unflagged run-args entry into run-args — and adds <name> to the selection.
//
// It still only attempts: the result is proven the same way an adopt is (the files
// regenerated from the new selection must match the ones on disk, directive for
// directive) on a copy of .booth/ before anything is written. Lines booth config
// writes that were removed or changed cannot be expressed by adding a template, so
// they are refused — a reconfigure takes the catalog's line.

// intoProbeName is the template name validate and a refusing repair try --into
// with, to say whether it would work.
const intoProbeName = "local"

var (
	intoNamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]*$`)
	argLinePattern  = regexp.MustCompile(`^arg ([A-Za-z_][A-Za-z0-9_]*)=(.*)$`)
)

// intoPlan is what --into would move, and the selection that results.
type intoPlan struct {
	name     string
	params   [][2]string // NAME, VALUE — from added `arg` lines, in file order
	segments []intoSegment
	runArgs  []runArgPair

	template string    // the .booth/templates/<name>.toml text
	flags    initFlags // the booth's flags with <name> selected and its edits lifted
	adopt    adoptResult
}

type intoSegment struct {
	band  int
	lines []string // comments kept with their directive, then the directive
}

func (p intoPlan) templatePath(targetPath string) string {
	return filepath.Join(targetPath, ".booth", "templates", p.name+".toml")
}

// describe lists what moves, one line each.
func (p intoPlan) describe() []string {
	var lines []string
	for _, seg := range p.segments {
		for _, line := range seg.lines {
			lines = append(lines, fmt.Sprintf("Boothfile--%d  %s", seg.band, line))
		}
	}
	for _, param := range p.params {
		lines = append(lines, fmt.Sprintf("param        %s=%s", param[0], param[1]))
	}
	for _, pair := range p.runArgs {
		lines = append(lines, fmt.Sprintf("run-args     %s", pair))
	}
	return lines
}

// planInto works out what --into <name> moves for the booth at targetPath, and
// proves it on a copy of .booth/. Nothing in targetPath is written. It returns the
// reasons it cannot, if it cannot.
func planInto(version, targetPath, name string, baseline boothBaseline, cli initFlags) (intoPlan, []string) {
	plan := intoPlan{name: name}
	if !intoNamePattern.MatchString(name) {
		return plan, []string{fmt.Sprintf("--into %q: a template name is lowercase letters, digits, '.', '_' and '-'", name)}
	}

	base := baseline.flags
	base.selectDSL = strings.Join(base.selectDSLs, "/")
	if len(base.selectDSLs) > 0 {
		templatesPath, cleanup, err := adoptTemplatesPath(version, targetPath, base, cli)
		defer cleanup()
		if err != nil {
			return plan, []string{err.Error()}
		}
		base.templatesPath = templatesPath
	}
	if reason := intoNameTaken(name, base.templatesPath, targetPath); reason != "" {
		return plan, []string{reason}
	}

	restore := muteStderr()
	expected, err := compileForAdopt(base, targetPath)
	if err != nil {
		restore()
		return plan, []string{"the recorded configuration no longer compiles: " + err.Error()}
	}
	diskConfig := readBoothFile(targetPath, "config.toml")
	lifted, _ := liftEdits(base, expected, diskConfig, targetPath)
	regen, err := compileForAdopt(lifted, targetPath)
	restore()
	if err != nil {
		return plan, []string{"the edits do not compile: " + err.Error()}
	}

	var reasons []string
	if regen.Boothfile != nil || readBoothFile(targetPath, "Boothfile") != "" {
		reasons = append(reasons, plan.takeBoothfile(readBoothFile(targetPath, "Boothfile"), regen.Boothfile)...)
	}
	reasons = append(reasons, plan.takeRunArgs(diskConfig, regen.Config.RunArgs)...)
	if len(reasons) > 0 {
		return plan, reasons
	}
	if len(plan.segments) == 0 && len(plan.params) == 0 && len(plan.runArgs) == 0 {
		return plan, []string{"no line needs moving: what blocks the repair is not a line booth config does not write"}
	}

	text, err := plan.templateText()
	if err != nil {
		return plan, []string{err.Error()}
	}
	plan.template = text
	return plan, plan.prove(version, targetPath, baseline, cli)
}

// intoNameTaken says why name cannot be the new template's, or "".
func intoNameTaken(name, templatesPath, targetPath string) string {
	for _, path := range []string{
		filepath.Join(targetPath, ".booth", "templates", name+".toml"),
		filepath.Join(targetPath, ".booth", "templates", name),
	} {
		if _, err := os.Stat(path); err == nil {
			return fmt.Sprintf("--into %s: %s already exists — pick another name", name, path)
		}
	}
	if registry, err := tmpl.LoadMergedRegistry(templatesPath, targetPath, io.Discard); err == nil {
		if _, taken := registry.ByName[name]; taken {
			return fmt.Sprintf("--into %s: a template named %s already exists — pick another name", name, name)
		}
	}
	return ""
}

// bandedDirective is one directive of the regenerated Boothfile, with the band and
// template it came from. Lines booth config adds outside any template (the `arg`
// pins, the APT snapshot) carry the band of the line before them, or -1.
type bandedDirective struct {
	text   string
	band   int
	source string
}

func bandedDirectives(bf *output.BoothfileContent) []bandedDirective {
	if bf == nil {
		return nil
	}
	var fromSpans []bandedDirective
	for _, span := range bf.Spans {
		for _, d := range output.BoothfileDirectives(span.Content) {
			fromSpans = append(fromSpans, bandedDirective{text: d, band: span.Order, source: span.Source})
		}
	}
	var out []bandedDirective
	band, source, j := -1, "", 0
	for _, d := range output.BoothfileDirectives(bf.Content) {
		if j < len(fromSpans) && fromSpans[j].text == d {
			band, source = fromSpans[j].band, fromSpans[j].source
			out = append(out, fromSpans[j])
			j++
			continue
		}
		out = append(out, bandedDirective{text: d, band: band, source: source})
	}
	return out
}

// diskDirective is one directive of the Boothfile on disk with the comment lines
// directly above it.
type diskDirective struct {
	text     string
	comments []string
}

func diskDirectives(content string) []diskDirective {
	var out []diskDirective
	var comments []string
	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
			comments = nil
		case strings.HasPrefix(trimmed, "#"):
			if !output.IsOwnedComment(trimmed) {
				comments = append(comments, trimmed)
			}
		default:
			out = append(out, diskDirective{text: trimmed, comments: comments})
			comments = nil
		}
	}
	return out
}

// takeBoothfile collects the Boothfile lines booth config does not write, placed in
// bands between their neighbours, and the reasons it cannot.
func (p *intoPlan) takeBoothfile(diskContent string, regen *output.BoothfileContent) []string {
	disk := diskDirectives(diskContent)
	want := bandedDirectives(regen)

	diskTexts := make([]string, len(disk))
	for i, d := range disk {
		diskTexts[i] = d.text
	}
	wantTexts := make([]string, len(want))
	for i, d := range want {
		wantTexts[i] = d.text
	}
	diskMatch, wantMatched := alignLines(diskTexts, wantTexts)

	unmatchedOnDisk := map[string]bool{}
	for i, m := range diskMatch {
		if m < 0 {
			unmatchedOnDisk[disk[i].text] = true
		}
	}
	var reasons []string
	for i, matched := range wantMatched {
		switch {
		case matched:
		case unmatchedOnDisk[want[i].text]:
			reasons = append(reasons, fmt.Sprintf("Boothfile `%s` — booth config writes this line at another place: "+
				"the lines were reordered, which a template cannot undo", want[i].text))
		default:
			reasons = append(reasons, fmt.Sprintf("Boothfile `%s` — booth config writes this line, but the file does not have it; "+
				"--into can only add lines, so a reconfigure has to take it", want[i].text))
		}
	}
	if len(reasons) > 0 {
		return reasons
	}

	used := map[int]bool{}
	for i := 0; i < len(disk); {
		if diskMatch[i] >= 0 {
			i++
			continue
		}
		start := i
		for i < len(disk) && diskMatch[i] < 0 {
			i++
		}

		var lines []string
		for _, d := range disk[start:i] {
			if m := argLinePattern.FindStringSubmatch(d.text); m != nil {
				p.params = append(p.params, [2]string{m[1], m[2]})
				continue
			}
			lines = append(append(lines, d.comments...), d.text)
		}
		if len(lines) == 0 {
			continue
		}

		lo, loSource, hi, hiSource := -1, "", 100, "￿"
		if start > 0 {
			prev := want[diskMatch[start-1]]
			lo, loSource = prev.band, prev.source
		}
		if i < len(disk) {
			next := want[diskMatch[i]]
			hi, hiSource = next.band, next.source
		}
		band, ok := pickBand(p.name, lo, loSource, hi, hiSource)
		if !ok {
			return []string{fmt.Sprintf("Boothfile `%s` sits where no order band of template %s lands (between band %d of %s and band %d of %s)",
				disk[start].text, p.name, lo, loSource, hi, hiSource)}
		}
		if used[band] {
			return []string{fmt.Sprintf("Boothfile `%s` would need band %d, which another moved line already takes", disk[start].text, band)}
		}
		used[band] = true
		p.segments = append(p.segments, intoSegment{band: band, lines: lines})
	}
	sort.Slice(p.segments, func(a, b int) bool { return p.segments[a].band < p.segments[b].band })
	return nil
}

// pickBand chooses the order band for a segment of template name that must land
// after band lo (from template loSource) and before band hi (from hiSource):
// segments sort by band, then by template name. A band strictly between wins — the
// midpoint — so the name does not matter; else a shared band, if the name sorts
// on the right side.
func pickBand(name string, lo int, loSource string, hi int, hiSource string) (int, bool) {
	var inside, shared []int
	for b := max(lo, 0); b <= min(hi, 99); b++ {
		afterLo := b > lo || (b == lo && name > loSource)
		beforeHi := b < hi || (b == hi && name < hiSource)
		if !afterLo || !beforeHi {
			continue
		}
		if b > lo && b < hi {
			inside = append(inside, b)
		} else {
			shared = append(shared, b)
		}
	}
	if len(inside) > 0 {
		mid := (lo + hi) / 2
		return min(max(mid, inside[0]), inside[len(inside)-1]), true
	}
	if len(shared) > 0 {
		return shared[0], true
	}
	return 0, false
}

// alignLines matches a against b in order (longest common subsequence): for each
// line of a, the index of the line of b it matches, or -1; and which lines of b
// were matched.
func alignLines(a, b []string) ([]int, []bool) {
	n, m := len(a), len(b)
	lcs := make([][]int, n+1)
	for i := range lcs {
		lcs[i] = make([]int, m+1)
	}
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if a[i] == b[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else {
				lcs[i][j] = max(lcs[i+1][j], lcs[i][j+1])
			}
		}
	}
	aMatch := make([]int, n)
	bMatched := make([]bool, m)
	for i := range aMatch {
		aMatch[i] = -1
	}
	for i, j := 0, 0; i < n && j < m; {
		switch {
		case a[i] == b[j]:
			aMatch[i], bMatched[j] = j, true
			i++
			j++
		case lcs[i+1][j] >= lcs[i][j+1]:
			i++
		default:
			j++
		}
	}
	return aMatch, bMatched
}

// takeRunArgs collects the run-args entries on disk that no flag and no selected
// template writes.
func (p *intoPlan) takeRunArgs(diskConfig string, regenArgs []string) []string {
	if diskConfig == "" {
		return nil
	}
	var disk map[string]interface{}
	if _, err := toml.Decode(diskConfig, &disk); err != nil {
		return []string{"config.toml is not valid TOML: " + err.Error()}
	}
	diskArgs, ok := stringList(disk["run-args"])
	if !ok {
		return []string{"config.toml `run-args` is not a list of strings"}
	}

	remaining := map[string]int{}
	for _, pair := range runArgPairs(regenArgs) {
		remaining[pair.key()]++
	}
	for _, pair := range runArgPairs(diskArgs) {
		if remaining[pair.key()] > 0 {
			remaining[pair.key()]--
			continue
		}
		p.runArgs = append(p.runArgs, pair)
	}
	var reasons []string
	for key, count := range remaining {
		if count > 0 {
			reasons = append(reasons, fmt.Sprintf("config.toml run-args `%s` — booth config writes it, but the file does not have it; "+
				"--into can only add entries", key))
		}
	}
	sort.Strings(reasons)
	return reasons
}

// templateText renders the plan as a project template.
func (p intoPlan) templateText() (string, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "# Lines booth config does not write itself, moved here from .booth/ by\n"+
		"# `booth config repair --into %s`. This template is selected as %s; edit it freely.\n", p.name, p.name)
	b.WriteString("cb-version = \"1.0.0\"\n")
	if len(p.runArgs) > 0 {
		b.WriteString("run-args = [\n")
		for _, pair := range p.runArgs {
			b.WriteString("    ")
			if pair.flag != "" {
				b.WriteString(tomlQuote(pair.flag) + ", ")
			}
			b.WriteString(tomlQuote(pair.value) + ",\n")
		}
		b.WriteString("]\n")
	}
	for _, param := range p.params {
		fmt.Fprintf(&b, "\n[params.%s]\ndefault = %s\n", param[0], tomlQuote(param[1]))
	}
	if len(p.segments) > 0 {
		b.WriteString("\n[segments]\n")
		for _, seg := range p.segments {
			body := strings.Join(seg.lines, "\n") + "\n"
			if strings.Contains(body, "'''") {
				return "", fmt.Errorf("Boothfile `%s` holds ''' and cannot be written into a template as is", seg.lines[len(seg.lines)-1])
			}
			fmt.Fprintf(&b, "\"Boothfile--%d\" = '''\n%s'''\n", seg.band, body)
		}
	}
	return b.String(), nil
}

func tomlQuote(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\t", `\t`, "\r", `\r`)
	return `"` + r.Replace(s) + `"`
}

// prove writes the template into a copy of .booth/, selects it, and reads the copy
// back the way an adopt does: it must match exactly, losing no comment.
func (p *intoPlan) prove(version, targetPath string, baseline boothBaseline, cli initFlags) []string {
	scratch, err := os.MkdirTemp("", "booth-repair-into-")
	if err != nil {
		return []string{err.Error()}
	}
	defer os.RemoveAll(scratch)
	if err := copyBoothForProof(filepath.Join(targetPath, ".booth"), filepath.Join(scratch, ".booth")); err != nil {
		return []string{"could not copy .booth/ to check the result: " + err.Error()}
	}
	path := p.templatePath(scratch)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return []string{err.Error()}
	}
	if err := os.WriteFile(path, []byte(p.template), 0o644); err != nil {
		return []string{err.Error()}
	}

	base := baseline.flags
	base.selectDSLs = append(append([]string{}, base.selectDSLs...), p.name)
	adopt := adoptEdits(version, scratch, base, cli)
	switch {
	case !adopt.adopted && len(adopt.reasons) > 0:
		return adopt.reasons
	case !adopt.adopted:
		return []string{"the booth with the template selected still does not read back"}
	case len(adopt.lost) > 0:
		var reasons []string
		for _, c := range adopt.lost {
			reasons = append(reasons, fmt.Sprintf("the rewrite would remove the comment at %s:%d  %s", c.file, c.Line, c.Text))
		}
		return reasons
	}
	p.adopt = adopt
	p.flags = adopt.flags
	return nil
}

// copyBoothForProof copies .booth/ for the proof — everything a compile reads,
// leaving out the cache and runtime folders, which can be large and are not read.
func copyBoothForProof(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		if d.IsDir() && (rel == "cache" || rel == ".tmp" || rel == "cache-seed" || rel == "shared-seed") {
			return filepath.SkipDir
		}
		target := filepath.Join(dst, rel)
		switch {
		case d.IsDir():
			return os.MkdirAll(target, 0o755)
		case d.Type()&fs.ModeSymlink != 0:
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return os.Symlink(link, target)
		case d.Type().IsRegular():
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			return os.WriteFile(target, data, 0o644)
		}
		return nil
	})
}
