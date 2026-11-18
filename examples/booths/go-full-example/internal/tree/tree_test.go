package tree

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// helper to create files/dirs
func mustMkdirAll(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
}

func mustWriteFile(t *testing.T, path string, data string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
}

func TestRenderBasic(t *testing.T) {
	dir := t.TempDir()
	// structure:
	// dir/
	//   a.txt
	//   b/
	//     c.txt
	//   .hidden
	mustWriteFile(t, filepath.Join(dir, "a.txt"), "hello")
	mustMkdirAll(t, filepath.Join(dir, "b"))
	mustWriteFile(t, filepath.Join(dir, "b", "c.txt"), "world")
	mustWriteFile(t, filepath.Join(dir, ".hidden"), "secret")

	out, err := Render(dir, Options{UseEmojis: true})
	if err != nil {
		t.Fatalf("Render error: %v", err)
	}

	root := filepath.Base(dir)

	// Hidden file should be excluded by default
	expectLines := []string{
		"📁 " + root,
		"├─ 📄 a.txt",
		"└─ 📁 b",
		"   └─ 📄 c.txt",
	}
	expect := strings.Join(expectLines, "\n") + "\n"
	if out != expect {
		t.Fatalf("unexpected output:\n--- got ---\n%q\n--- want ---\n%q\n", out, expect)
	}
}

func TestRenderAllAndMaxDepth(t *testing.T) {
	dir := t.TempDir()
	mustMkdirAll(t, filepath.Join(dir, "b"))
	mustWriteFile(t, filepath.Join(dir, "b", "c.txt"), "x")
	mustWriteFile(t, filepath.Join(dir, ".hidden"), "h")
	mustWriteFile(t, filepath.Join(dir, "a.txt"), "a")

	// MaxDepth=1 should show only root's immediate children; grandchildren omitted
	out, err := Render(dir, Options{All: true, UseEmojis: true, MaxDepth: 1})
	if err != nil {
		t.Fatalf("Render error: %v", err)
	}
	root := filepath.Base(dir)
	// Order: .hidden, a.txt, b (case-insensitive sort)
	expectLines := []string{
		"📁 " + root,
		"├─ 📄 .hidden",
		"├─ 📄 a.txt",
		"└─ 📁 b",
	}
	expect := strings.Join(expectLines, "\n") + "\n"
	if out != expect {
		t.Fatalf("unexpected output for MaxDepth=1:\n--- got ---\n%q\n--- want ---\n%q\n", out, expect)
	}
}

func TestRenderDirsOnly(t *testing.T) {
	dir := t.TempDir()
	mustMkdirAll(t, filepath.Join(dir, "alpha"))
	mustMkdirAll(t, filepath.Join(dir, "beta"))
	mustWriteFile(t, filepath.Join(dir, "file.txt"), "f")

	out, err := Render(dir, Options{DirsOnly: true, UseEmojis: true})
	if err != nil {
		t.Fatalf("Render error: %v", err)
	}
	root := filepath.Base(dir)
	// alpha then beta in sort order
	expectLines := []string{
		"📁 " + root,
		"├─ 📁 alpha",
		"└─ 📁 beta",
	}
	expect := strings.Join(expectLines, "\n") + "\n"
	if out != expect {
		t.Fatalf("unexpected output for DirsOnly:\n--- got ---\n%q\n--- want ---\n%q\n", out, expect)
	}
}
