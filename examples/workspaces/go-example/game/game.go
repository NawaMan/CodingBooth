// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package game holds the rules of 4096, a sliding-tile puzzle on a 4x4 grid:
// a move slides every tile one way, two equal tiles that meet merge into their
// sum (at most once per tile per move), and a new 2 or 4 appears after every
// move that changed the board. Reaching a 4096 tile wins; a full board with no
// equal neighbours loses.
package game

import "math/rand/v2"

// Size is the width and height of the board.
const Size = 4

// Goal is the tile that wins the game.
const Goal = 4096

// Direction is the way a move slides the tiles.
type Direction int

const (
	Left Direction = iota
	Right
	Up
	Down
)

// Game is one game in progress. The zero value is not usable: call New.
type Game struct {
	Board [Size][Size]int
	Score int
	Moves int
	rng   *rand.Rand
}

// New starts a game with two tiles, using seed for every random choice, so
// the same seed and the same moves always give the same game.
func New(seed uint64) *Game {
	g := &Game{rng: rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))}
	g.Spawn()
	g.Spawn()
	return g
}

// Spawn puts a 2 (nine times in ten) or a 4 on a random empty cell. It
// reports false when the board has no empty cell.
func (g *Game) Spawn() bool {
	var empty [][2]int
	for r := range Size {
		for c := range Size {
			if g.Board[r][c] == 0 {
				empty = append(empty, [2]int{r, c})
			}
		}
	}
	if len(empty) == 0 {
		return false
	}
	cell := empty[g.rng.IntN(len(empty))]
	value := 2
	if g.rng.IntN(10) == 0 {
		value = 4
	}
	g.Board[cell[0]][cell[1]] = value
	return true
}

// Move slides the board in d, adds what merged to the score, and spawns a
// tile. It reports false, and changes nothing, when the move moves no tile.
func (g *Game) Move(d Direction) bool {
	changed := false
	for i := range Size {
		line := g.line(d, i)
		slid, gained := SlideLine(line)
		if slid != line {
			changed = true
			g.setLine(d, i, slid)
			g.Score += gained
		}
	}
	if changed {
		g.Moves++
		g.Spawn()
	}
	return changed
}

// SlideLine slides one line toward its index 0 and merges equal neighbours,
// each tile at most once: [2 2 2 2] gives [4 4 0 0], not [8 0 0 0]. It returns
// the new line and the sum of the merged tiles.
func SlideLine(line [Size]int) ([Size]int, int) {
	var out [Size]int
	n, gained := 0, 0
	merged := false // out[n-1] is the result of a merge in this move
	for _, v := range line {
		if v == 0 {
			continue
		}
		if n > 0 && out[n-1] == v && !merged {
			out[n-1] *= 2
			gained += out[n-1]
			merged = true
			continue
		}
		out[n] = v
		n++
		merged = false
	}
	return out, gained
}

// line reads row or column i so that index 0 is the edge the tiles slide to.
func (g *Game) line(d Direction, i int) [Size]int {
	var l [Size]int
	for j := range Size {
		r, c := cell(d, i, j)
		l[j] = g.Board[r][c]
	}
	return l
}

func (g *Game) setLine(d Direction, i int, l [Size]int) {
	for j := range Size {
		r, c := cell(d, i, j)
		g.Board[r][c] = l[j]
	}
}

// cell maps position j of line i, read in direction d, to a board cell.
func cell(d Direction, i, j int) (int, int) {
	switch d {
	case Left:
		return i, j
	case Right:
		return i, Size - 1 - j
	case Up:
		return j, i
	default: // Down
		return Size - 1 - j, i
	}
}

// Won reports whether the board holds the Goal tile (or more).
func (g *Game) Won() bool {
	for r := range Size {
		for c := range Size {
			if g.Board[r][c] >= Goal {
				return true
			}
		}
	}
	return false
}

// CanMove reports whether any move would change the board: an empty cell, or
// two equal tiles side by side.
func (g *Game) CanMove() bool {
	for r := range Size {
		for c := range Size {
			v := g.Board[r][c]
			if v == 0 {
				return true
			}
			if c+1 < Size && g.Board[r][c+1] == v {
				return true
			}
			if r+1 < Size && g.Board[r+1][c] == v {
				return true
			}
		}
	}
	return false
}

// Max is the largest tile on the board.
func (g *Game) Max() int {
	m := 0
	for r := range Size {
		for c := range Size {
			m = max(m, g.Board[r][c])
		}
	}
	return m
}
