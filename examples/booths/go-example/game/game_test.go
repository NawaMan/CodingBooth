// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package game

import "testing"

func TestSlideLine(t *testing.T) {
	cases := []struct {
		in     [Size]int
		out    [Size]int
		gained int
	}{
		{[Size]int{0, 0, 0, 0}, [Size]int{0, 0, 0, 0}, 0},
		{[Size]int{0, 0, 0, 2}, [Size]int{2, 0, 0, 0}, 0},
		{[Size]int{2, 0, 2, 0}, [Size]int{4, 0, 0, 0}, 4},
		{[Size]int{2, 2, 2, 2}, [Size]int{4, 4, 0, 0}, 8},   // each tile merges once
		{[Size]int{4, 4, 8, 0}, [Size]int{8, 8, 0, 0}, 8},   // a merged 8 does not merge again
		{[Size]int{2, 2, 2, 0}, [Size]int{4, 2, 0, 0}, 4},   // the pair nearest the edge merges
		{[Size]int{2, 4, 8, 16}, [Size]int{2, 4, 8, 16}, 0}, // nothing to do
		{[Size]int{2048, 2048, 0, 0}, [Size]int{4096, 0, 0, 0}, 4096},
	}
	for _, c := range cases {
		out, gained := SlideLine(c.in)
		if out != c.out || gained != c.gained {
			t.Errorf("SlideLine(%v) = %v, %d; want %v, %d", c.in, out, gained, c.out, c.gained)
		}
	}
}

func TestMoveEachDirection(t *testing.T) {
	start := [Size][Size]int{
		{2, 0, 0, 2},
		{0, 0, 0, 0},
		{0, 0, 0, 0},
		{2, 0, 0, 0},
	}
	want := map[Direction][Size][Size]int{
		Left:  {{4, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {2, 0, 0, 0}},
		Right: {{0, 0, 0, 4}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 2}},
		Up:    {{4, 0, 0, 2}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}},
		Down:  {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {4, 0, 0, 2}},
	}
	for d, w := range want {
		g := New(1)
		g.Board = start
		if !g.Move(d) {
			t.Fatalf("move %d: reported no change", d)
		}
		// Every cell of w must match, except the one new tile Move spawned.
		spawned := 0
		for r := range Size {
			for c := range Size {
				if g.Board[r][c] == w[r][c] {
					continue
				}
				if w[r][c] == 0 && (g.Board[r][c] == 2 || g.Board[r][c] == 4) {
					spawned++
					continue
				}
				t.Errorf("move %d: cell %d,%d = %d, want %d", d, r, c, g.Board[r][c], w[r][c])
			}
		}
		if spawned != 1 {
			t.Errorf("move %d: %d new tiles, want 1", d, spawned)
		}
		if g.Score != 4 {
			t.Errorf("move %d: score %d, want 4", d, g.Score)
		}
	}
}

func TestMoveThatChangesNothing(t *testing.T) {
	g := New(1)
	g.Board = [Size][Size]int{{2, 4, 8, 16}}
	before := g.Board
	if g.Move(Left) {
		t.Fatal("Move(Left) reported a change on a line already packed left")
	}
	if g.Board != before || g.Moves != 0 {
		t.Fatal("a move that moves nothing must not spawn a tile or count")
	}
}

func TestNewIsSeeded(t *testing.T) {
	a, b := New(7), New(7)
	for _, d := range []Direction{Left, Up, Right, Down, Left} {
		a.Move(d)
		b.Move(d)
	}
	if a.Board != b.Board || a.Score != b.Score {
		t.Fatal("the same seed and moves gave different games")
	}
	tiles := 0
	for r := range Size {
		for c := range Size {
			if New(7).Board[r][c] != 0 {
				tiles++
			}
		}
	}
	if tiles != 2 {
		t.Fatalf("a new game has %d tiles, want 2", tiles)
	}
}

func TestWonAndCanMove(t *testing.T) {
	g := New(1)
	g.Board = [Size][Size]int{
		{2, 4, 2, 4},
		{4, 2, 4, 2},
		{2, 4, 2, 4},
		{4, 2, 4, 2},
	}
	if g.CanMove() {
		t.Error("a full board with no equal neighbours must be lost")
	}
	if g.Won() {
		t.Error("no 4096 tile, yet Won")
	}
	g.Board[3][3] = 4 // now equal to its left neighbour
	if !g.CanMove() {
		t.Error("two equal neighbours: a move is possible")
	}
	g.Board[0][0] = Goal
	if !g.Won() {
		t.Error("a 4096 tile must win")
	}
	if g.Max() != Goal {
		t.Errorf("Max = %d, want %d", g.Max(), Goal)
	}
}
