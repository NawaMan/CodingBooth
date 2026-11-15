// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// go4096 is a terminal sliding-tile puzzle: slide the tiles with the arrow
// keys (or WASD), merge equal ones, and reach 4096.
//
//	go4096              play (q or Ctrl-C quits)
//	go4096 --seed 42    play a game you can replay
//	go4096 --demo       play a fixed game by itself and print the end; needs no terminal
//
// No dependencies: raw key input comes from `stty` on /dev/tty.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"go-example/game"
)

func main() {
	seed := flag.Uint64("seed", 0, "random seed (0: from the clock)")
	demo := flag.Bool("demo", false, "play a fixed game without a terminal and print how it ends")
	flag.Parse()

	if *demo {
		os.Exit(runDemo(*seed))
	}
	if *seed == 0 {
		*seed = uint64(time.Now().UnixNano())
	}
	if err := play(game.New(*seed)); err != nil {
		fmt.Fprintln(os.Stderr, "go4096:", err)
		os.Exit(1)
	}
}

// runDemo plays left, down, right, down... until the game ends or 2000 moves,
// prints the final board, and returns 0. Seed 0 means seed 1, so the demo is
// the same every time.
func runDemo(seed uint64) int {
	if seed == 0 {
		seed = 1
	}
	g := game.New(seed)
	order := []game.Direction{game.Left, game.Down, game.Right, game.Down}
	for i := 0; i < 2000 && g.CanMove() && !g.Won(); i++ {
		if !g.Move(order[i%len(order)]) {
			// Stuck that way: try the others before giving up.
			for _, d := range []game.Direction{game.Left, game.Down, game.Right, game.Up} {
				if g.Move(d) {
					break
				}
			}
		}
	}
	fmt.Print(render(g, "\n", false))
	fmt.Printf("demo: seed %d, %d moves, score %d, best tile %d\n", seed, g.Moves, g.Score, g.Max())
	return 0
}

// play runs the interactive game on /dev/tty in raw mode.
func play(g *game.Game) error {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("needs a terminal (try --demo): %w", err)
	}
	defer tty.Close()

	saved, err := stty(tty, "-g")
	if err != nil {
		return fmt.Errorf("stty: %w", err)
	}
	if _, err := stty(tty, "raw", "-echo"); err != nil {
		return fmt.Errorf("stty raw: %w", err)
	}
	restore := func() {
		stty(tty, strings.TrimSpace(saved))
		fmt.Fprint(tty, "\033[?25h") // show the cursor again
	}
	defer restore()
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGHUP)
	go func() { <-sig; restore(); os.Exit(1) }()

	fmt.Fprint(tty, "\033[?25l") // hide the cursor
	in := bufio.NewReader(tty)
	message := "arrows or WASD to slide, q to quit"
	won := false
	for {
		fmt.Fprint(tty, "\033[H\033[2J", render(g, "\r\n", true), "\r\n", message, "\r\n")
		if !g.CanMove() {
			fmt.Fprint(tty, "No move left. Game over.\r\n")
			return nil
		}
		d, quit := readKey(in)
		if quit {
			fmt.Fprint(tty, "Bye.\r\n")
			return nil
		}
		if d < 0 {
			continue
		}
		if g.Move(game.Direction(d)) {
			message = "arrows or WASD to slide, q to quit"
		} else {
			message = "nothing moves that way"
		}
		if g.Won() && !won {
			won = true
			message = "4096! You won. Keep going, or q to quit"
		}
	}
}

// readKey reads one key: a direction (as a game.Direction), quit, or -1 for
// a key that does nothing.
func readKey(in *bufio.Reader) (int, bool) {
	b, err := in.ReadByte()
	if err != nil {
		return -1, true
	}
	switch b {
	case 'q', 'Q', 3, 4: // q, Ctrl-C, Ctrl-D
		return -1, true
	case 'a', 'A', 'h':
		return int(game.Left), false
	case 'd', 'D', 'l':
		return int(game.Right), false
	case 'w', 'W', 'k':
		return int(game.Up), false
	case 's', 'S', 'j':
		return int(game.Down), false
	case 0x1b: // ESC [ A..D: an arrow key
		if b2, _ := in.ReadByte(); b2 != '[' {
			return -1, false
		}
		switch b3, _ := in.ReadByte(); b3 {
		case 'A':
			return int(game.Up), false
		case 'B':
			return int(game.Down), false
		case 'C':
			return int(game.Right), false
		case 'D':
			return int(game.Left), false
		}
	}
	return -1, false
}

// render draws the board and the score, lines ending in eol ("\r\n" in raw
// mode), with coloured tiles when colored is set.
func render(g *game.Game, eol string, colored bool) string {
	var b strings.Builder
	fmt.Fprintf(&b, "  4096    score %d    moves %d%s", g.Score, g.Moves, eol)
	line := "+" + strings.Repeat("------+", game.Size)
	b.WriteString(line + eol)
	for r := range game.Size {
		b.WriteString("|")
		for c := range game.Size {
			if v := g.Board[r][c]; v == 0 {
				b.WriteString("      |")
			} else if colored {
				fmt.Fprintf(&b, "%s%5d \033[0m|", color(v), v)
			} else {
				fmt.Fprintf(&b, "%5d |", v)
			}
		}
		b.WriteString(eol + line + eol)
	}
	return b.String()
}

// color picks a 256-colour background per tile value, brighter as it grows.
func color(v int) string {
	shades := []int{230, 223, 216, 209, 203, 197, 220, 214, 208, 202, 196, 160}
	i := 0
	for x := v; x > 2 && i < len(shades)-1; x /= 2 {
		i++
	}
	return fmt.Sprintf("\033[30;48;5;%dm", shades[i])
}

// stty runs stty on the terminal and returns what it prints.
func stty(tty *os.File, args ...string) (string, error) {
	cmd := exec.Command("stty", args...)
	cmd.Stdin = tty
	out, err := cmd.Output()
	return string(out), err
}
