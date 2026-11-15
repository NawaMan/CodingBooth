package main

import (
	"flag"
	"fmt"
	"os"

	"treemoji/internal/tree"
)

func main() {
	// Flags
	all := flag.Bool("a", false, "All files, include hidden (like tree -a)")
	dirsOnly := flag.Bool("d", false, "List directories only")
	maxDepth := flag.Int("L", 0, "Max display depth of the directory tree (0 = unlimited)")
	noEmoji := flag.Bool("no-emoji", false, "Disable emojis in output")
	version := flag.Bool("version", false, "Print version and exit")

	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Treemoji — a tiny tree-like CLI with emojis\n")
		fmt.Fprintf(flag.CommandLine.Output(), "Usage: treemoji [options] [directory]\n\n")
		fmt.Fprintf(flag.CommandLine.Output(), "Options:\n")
		flag.PrintDefaults()
	}

	flag.Parse()

	if *version {
		fmt.Println("treemoji v0.1.0")
		return
	}

	var root string
	switch flag.NArg() {
	case 0:
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			os.Exit(1)
		}
		root = cwd
	case 1:
		root = flag.Arg(0)
	default:
		flag.Usage()
		os.Exit(2)
	}

	opts := tree.Options{
		All:       *all,
		DirsOnly:  *dirsOnly,
		MaxDepth:  *maxDepth,
		UseEmojis: !*noEmoji,
	}

	out, err := tree.Render(root, opts)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	fmt.Print(out)
}
