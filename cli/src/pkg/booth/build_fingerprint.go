// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"hash"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// FingerprintLabel is the image label holding the build fingerprint. A start
// whose fingerprint matches the label on the existing local image skips
// `docker build` entirely.
//
// Why skip rather than trust the build cache: a fully cached build still
// contacts the registry before it reaches the cache — for the
// `# syntax=docker/dockerfile:...` frontend and the FROM tag — so during a
// Docker Hub outage a booth whose image was already built would not start.
const FingerprintLabel = "cb.fingerprint"

// Fingerprint limits: past either, a start just builds as it always did,
// rather than hashing a whole repository (`copy . /somewhere`) on every start.
const (
	fingerprintMaxBytes = 50 * 1024 * 1024
	fingerprintMaxFiles = 5000
)

// ImageIDResolver returns the local image ID for an image reference, without
// contacting a registry. ok is false when the image is not present locally.
type ImageIDResolver func(ref string) (id string, ok bool)

// BuildFingerprintInput is everything a local build reads.
type BuildFingerprintInput struct {
	// Dockerfile is the Dockerfile text (generated or user-written).
	Dockerfile string
	// BuildFlags is the docker build argument list, without -f <path> (the
	// generated Dockerfile lives at a fresh temp path on every start) and
	// without the fingerprint label itself.
	BuildFlags []string
	// ContextDir is the build context directory.
	ContextDir string
	// ImageID resolves FROM and COPY --from images to their local IDs.
	ImageID ImageIDResolver
}

// ComputeBuildFingerprint returns a content hash over every input of a local
// build: the Dockerfile text, the build flags (build args, labels, platform),
// the local IDs of every image the build starts from or copies from, and the
// content of every file COPY/ADD reads from the build context.
//
// It returns an empty fingerprint and a reason when the build cannot be
// fingerprinted safely — an image is not present locally, ADD fetches a URL,
// a RUN bind-mounts the context, a variable cannot be resolved, or the copied
// sources are too large. The caller then builds as usual.
func ComputeBuildFingerprint(input BuildFingerprintInput) (string, string) {
	sum := sha256.New()
	writeField(sum, "dockerfile", input.Dockerfile)
	for _, flag := range input.BuildFlags {
		writeField(sum, "flag", flag)
	}

	instructions := parseDockerfileInstructions(input.Dockerfile)
	overrides := buildArgValues(input.BuildFlags)
	vars := map[string]string{}
	for name, value := range overrides {
		vars[name] = value
	}
	stages := map[string]bool{}
	budget := &hashBudget{}

	for _, inst := range instructions {
		switch inst.keyword {
		case "ARG":
			for _, decl := range inst.args {
				name, value, hasDefault := strings.Cut(decl, "=")
				if _, overridden := overrides[name]; !overridden && hasDefault {
					vars[name] = unquote(value)
				}
			}
		case "ENV":
			for _, decl := range inst.args {
				if name, value, ok := strings.Cut(decl, "="); ok {
					vars[name] = unquote(value)
				}
			}
		case "FROM":
			_, rest := splitFlags(inst.args)
			if len(rest) == 0 {
				return "", "FROM without an image"
			}
			ref, reason := expandVars(rest[0], vars)
			if reason != "" {
				return "", reason
			}
			if reason := hashImage(sum, ref, stages, input.ImageID); reason != "" {
				return "", reason
			}
			if len(rest) >= 3 && strings.EqualFold(rest[1], "AS") {
				stages[strings.ToLower(rest[2])] = true
			}
		case "RUN":
			flags, _ := splitFlags(inst.args)
			for _, flag := range flags {
				if mount, ok := strings.CutPrefix(flag, "--mount="); ok && readsContext(mount) {
					return "", "a RUN bind-mounts the build context"
				}
			}
		case "COPY", "ADD":
			if !inst.parsed {
				return "", fmt.Sprintf("cannot parse %s arguments", inst.keyword)
			}
			flags, rest := splitFlags(inst.args)
			if len(rest) < 2 {
				return "", inst.keyword + " without a source and a destination"
			}
			from := ""
			for _, flag := range flags {
				if value, ok := strings.CutPrefix(flag, "--from="); ok {
					from = value
				}
			}
			if from != "" {
				ref, reason := expandVars(from, vars)
				if reason != "" {
					return "", reason
				}
				if reason := hashImage(sum, ref, stages, input.ImageID); reason != "" {
					return "", reason
				}
				continue
			}
			for _, source := range rest[:len(rest)-1] {
				if strings.HasPrefix(source, "<<") {
					// A heredoc source: its content is in the Dockerfile text.
					continue
				}
				expanded, reason := expandVars(source, vars)
				if reason != "" {
					return "", reason
				}
				if inst.keyword == "ADD" && isRemoteSource(expanded) {
					return "", "ADD fetches a remote source"
				}
				if reason := hashContextSource(sum, input.ContextDir, expanded, budget); reason != "" {
					return "", reason
				}
			}
		}
	}

	return hex.EncodeToString(sum.Sum(nil)), ""
}

func writeField(sum hash.Hash, kind string, value string) {
	fmt.Fprintf(sum, "%s %d:%s\n", kind, len(value), value)
}

// hashImage adds a FROM / COPY --from image's local ID to the fingerprint.
// Stage names and scratch carry no image of their own.
func hashImage(sum hash.Hash, ref string, stages map[string]bool, imageID ImageIDResolver) string {
	if stages[strings.ToLower(ref)] || ref == "scratch" {
		return ""
	}
	if imageID == nil {
		return "no image resolver"
	}
	id, ok := imageID(ref)
	if !ok {
		return fmt.Sprintf("image '%s' is not present locally", ref)
	}
	writeField(sum, "image", ref+"="+id)
	return ""
}

type hashBudget struct {
	bytes int64
	files int
}

func (budget *hashBudget) spend(bytes int64) string {
	budget.files++
	budget.bytes += bytes
	if budget.files > fingerprintMaxFiles {
		return fmt.Sprintf("copies more than %d files", fingerprintMaxFiles)
	}
	if budget.bytes > fingerprintMaxBytes {
		return fmt.Sprintf("copies more than %d MB", fingerprintMaxBytes/(1024*1024))
	}
	return ""
}

// hashContextSource hashes one COPY/ADD source pattern: which paths it matches
// in the build context, and the content of each. A pattern that matches nothing
// is recorded too, so a file appearing later changes the fingerprint.
func hashContextSource(sum hash.Hash, contextDir string, source string, budget *hashBudget) string {
	cleaned := filepath.Clean(filepath.FromSlash(strings.TrimPrefix(source, "/")))
	if cleaned == ".." || strings.HasPrefix(cleaned, ".."+string(filepath.Separator)) {
		return fmt.Sprintf("source '%s' is outside the build context", source)
	}
	writeField(sum, "source", source)
	matches, err := filepath.Glob(filepath.Join(contextDir, cleaned))
	if err != nil {
		return fmt.Sprintf("source '%s': %v", source, err)
	}
	sort.Strings(matches)
	for _, match := range matches {
		// COPY follows a symlinked source root, so walk what it points at.
		root, err := filepath.EvalSymlinks(match)
		if err != nil {
			return fmt.Sprintf("cannot read source '%s': %v", source, err)
		}
		matchRel, err := filepath.Rel(contextDir, match)
		if err != nil {
			return fmt.Sprintf("cannot read source '%s': %v", source, err)
		}
		walkErr := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			rel := matchRel + strings.TrimPrefix(path, root)
			info, err := entry.Info()
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)
			switch {
			case info.Mode()&fs.ModeSymlink != 0:
				target, err := os.Readlink(path)
				if err != nil {
					return err
				}
				writeField(sum, "link", rel+" -> "+target)
			case info.IsDir():
				writeField(sum, "dir", rel+" "+info.Mode().String())
			case info.Mode().IsRegular():
				if reason := budget.spend(info.Size()); reason != "" {
					return errBudget(reason)
				}
				writeField(sum, "file", fmt.Sprintf("%s %s %d", rel, info.Mode().String(), info.Size()))
				file, err := os.Open(path)
				if err != nil {
					return err
				}
				_, err = io.Copy(sum, file)
				file.Close()
				if err != nil {
					return err
				}
			default:
				writeField(sum, "special", rel+" "+info.Mode().String())
			}
			return nil
		})
		if walkErr != nil {
			if reason, ok := walkErr.(errBudget); ok {
				return string(reason)
			}
			return fmt.Sprintf("cannot read source '%s': %v", source, walkErr)
		}
	}
	return ""
}

type errBudget string

func (err errBudget) Error() string { return string(err) }

func isRemoteSource(source string) bool {
	return strings.Contains(source, "://") || strings.HasPrefix(source, "git@")
}

// readsContext reports whether a RUN --mount reads the build context: a bind
// mount (the default type) with no from=.
func readsContext(mount string) bool {
	mountType := "bind"
	hasFrom := false
	for _, option := range strings.Split(mount, ",") {
		key, value, _ := strings.Cut(option, "=")
		switch strings.TrimSpace(key) {
		case "type":
			mountType = strings.TrimSpace(value)
		case "from":
			hasFrom = true
		}
	}
	return mountType == "bind" && !hasFrom
}

// buildArgValues collects --build-arg NAME=value pairs from docker build flags.
func buildArgValues(flags []string) map[string]string {
	values := map[string]string{}
	for index, flag := range flags {
		pair := ""
		if value, ok := strings.CutPrefix(flag, "--build-arg="); ok {
			pair = value
		} else if flag == "--build-arg" && index+1 < len(flags) {
			pair = flags[index+1]
		}
		if name, value, ok := strings.Cut(pair, "="); ok {
			values[name] = value
		}
	}
	return values
}

var dockerVarPattern = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)(:[-+][^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*)`)

// expandVars substitutes $NAME / ${NAME} / ${NAME:-default} from vars. A
// variable with no value is a reason not to fingerprint: guessing what Docker
// would substitute risks a stale image.
func expandVars(text string, vars map[string]string) (string, string) {
	reason := ""
	expanded := dockerVarPattern.ReplaceAllStringFunc(text, func(match string) string {
		parts := dockerVarPattern.FindStringSubmatch(match)
		name := parts[1]
		if name == "" {
			name = parts[3]
		}
		value, ok := vars[name]
		modifier := parts[2]
		switch {
		case strings.HasPrefix(modifier, ":-"):
			if !ok || value == "" {
				return modifier[2:]
			}
			return value
		case strings.HasPrefix(modifier, ":+"):
			if ok && value != "" {
				return modifier[2:]
			}
			return ""
		}
		if !ok {
			reason = fmt.Sprintf("cannot resolve $%s in '%s'", name, text)
		}
		return value
	})
	return expanded, reason
}

func unquote(value string) string {
	if len(value) >= 2 && (value[0] == '"' || value[0] == '\'') && value[len(value)-1] == value[0] {
		return value[1 : len(value)-1]
	}
	return value
}

// splitFlags splits instruction arguments into leading --flags and the rest.
func splitFlags(args []string) ([]string, []string) {
	index := 0
	for index < len(args) && strings.HasPrefix(args[index], "--") {
		index++
	}
	return args[:index], args[index:]
}

type dockerfileInstruction struct {
	keyword string
	args    []string
	// parsed is false when the arguments look like a JSON array that does not
	// decode; the sources are then unknown.
	parsed bool
}

var heredocPattern = regexp.MustCompile(`<<(-?)["']?([A-Za-z_][A-Za-z0-9_]*)["']?`)

// parseDockerfileInstructions reads the instructions the fingerprint needs:
// it joins backslash continuations, drops comments and blank lines, and skips
// heredoc bodies so a "COPY" line inside a RUN script is not taken for one.
func parseDockerfileInstructions(dockerfile string) []dockerfileInstruction {
	lines := strings.Split(strings.ReplaceAll(dockerfile, "\r\n", "\n"), "\n")
	var instructions []dockerfileInstruction
	for index := 0; index < len(lines); index++ {
		line := strings.TrimSpace(lines[index])
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		for strings.HasSuffix(line, "\\") && index+1 < len(lines) {
			index++
			next := strings.TrimSpace(lines[index])
			if strings.HasPrefix(next, "#") {
				continue
			}
			line = strings.TrimSuffix(line, "\\") + " " + next
		}
		line = strings.TrimSuffix(line, "\\")

		for _, heredoc := range heredocPattern.FindAllStringSubmatch(line, -1) {
			delimiter := heredoc[2]
			for index+1 < len(lines) {
				index++
				body := lines[index]
				if heredoc[1] == "-" {
					body = strings.TrimLeft(body, "\t")
				}
				if body == delimiter {
					break
				}
			}
		}

		keyword, rest, _ := strings.Cut(line, " ")
		args, parsed := instructionArgs(strings.TrimSpace(rest))
		instructions = append(instructions, dockerfileInstruction{
			keyword: strings.ToUpper(keyword),
			args:    args,
			parsed:  parsed,
		})
	}
	return instructions
}

// instructionArgs splits instruction arguments: leading --flags, then either
// whitespace-separated words or the JSON array form (COPY --chown=x ["a", "b"]).
func instructionArgs(rest string) ([]string, bool) {
	var flags []string
	for strings.HasPrefix(rest, "--") {
		flag, remaining, _ := strings.Cut(rest, " ")
		flags = append(flags, flag)
		rest = strings.TrimSpace(remaining)
	}
	if !strings.HasPrefix(rest, "[") {
		return append(flags, strings.Fields(rest)...), true
	}
	var array []string
	if json.Unmarshal([]byte(rest), &array) != nil {
		return append(flags, strings.Fields(rest)...), false
	}
	return append(flags, array...), true
}
