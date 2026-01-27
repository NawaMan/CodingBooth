package tree

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Options controls rendering behavior.
// MaxDepth: 0 means unlimited depth.
// If DirsOnly is true, files are omitted.
// If All is false, entries starting with '.' are omitted.
// UseEmojis enables emoji prefixes.
//
// This package focuses on deterministic output (sorted, stable).
// The Render function returns the full output as a string.
type Options struct {
	MaxDepth  int
	DirsOnly  bool
	All       bool
	UseEmojis bool
}

// Render returns the formatted tree for a root path using the provided options.
func Render(root string, opts Options) (string, error) {
	fi, err := os.Lstat(root)
	if err != nil {
		return "", err
	}

	if !fi.IsDir() {
		// Render single file
		name := filepath.Base(root)
		line, _ := formatLine(name, fi, 0, false, opts)
		return line + "\n", nil
	}

	b := &strings.Builder{}
	rootName := filepath.Base(root)
	// Show root line
	rootLine, _ := formatLine(rootName, fi, 0, false, opts)
	fmt.Fprintln(b, rootLine)

	err = renderDir(b, root, 1, nil, opts)
	if err != nil {
		return "", err
	}
	return b.String(), nil
}

// renderDir walks a directory and writes tree lines.
// prefixBits indicates for each ancestor whether there are more siblings at that level.
func renderDir(b *strings.Builder, dir string, depth int, prefixBits []bool, opts Options) error {
	if opts.MaxDepth > 0 && depth > opts.MaxDepth {
		return nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}

	filtered := make([]fs.DirEntry, 0, len(entries))
	for _, e := range entries {
		name := e.Name()
		if !opts.All && strings.HasPrefix(name, ".") {
			continue
		}
		if opts.DirsOnly && !e.IsDir() {
			continue
		}
		filtered = append(filtered, e)
	}

	sort.Slice(filtered, func(i, j int) bool {
		return strings.ToLower(filtered[i].Name()) < strings.ToLower(filtered[j].Name())
	})

	for i, e := range filtered {
		isLast := i == len(filtered)-1
		linePrefix := buildPrefix(prefixBits, isLast)

		info, lerr := e.Info()
		if lerr != nil {
			return lerr
		}

		label, _ := formatLine(e.Name(), info, depth, isLast, opts)
		fmt.Fprintln(b, linePrefix+label)

		if e.IsDir() {
			nextBits := append(prefixBits, !isLast)
			if err := renderDir(b, filepath.Join(dir, e.Name()), depth+1, nextBits, opts); err != nil {
				return err
			}
		}
	}
	return nil
}

func buildPrefix(prefixBits []bool, isLast bool) string {
	var sb strings.Builder
	// Draw all ancestor levels vertical guides
	for _, hasMore := range prefixBits {
		if hasMore {
			sb.WriteString("│  ")
		} else {
			sb.WriteString("   ")
		}
	}
	// Current level branch
	if isLast {
		sb.WriteString("└─ ")
	} else {
		sb.WriteString("├─ ")
	}
	return sb.String()
}

func formatLine(name string, info os.FileInfo, depth int, isLast bool, opts Options) (string, string) {
	// Returns displayLabel, emojiUsed
	emoji := ""
	if opts.UseEmojis {
		mode := info.Mode()
		switch {
		case mode&os.ModeSymlink != 0:
			emoji = "🔗 "
		case info.IsDir():
			emoji = "📁 "
		default:
			emoji = "📄 "
		}
	}
	return emoji + name, emoji
}

// ValidateOptions can be used by callers to check constraints.
func ValidateOptions(o Options) error {
	if o.MaxDepth < 0 {
		return errors.New("MaxDepth cannot be negative")
	}
	return nil
}
