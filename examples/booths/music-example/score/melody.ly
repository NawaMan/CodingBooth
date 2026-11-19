% The melody: four bars over Am - F - C - G, at 120 BPM.
% `just score` engraves it to out/melody.pdf and out/melody.midi;
% `just melody` plays the MIDI through FluidSynth.
\version "2.24.0"

\header { title = "Four Bars" composer = "music-example" tagline = ##f }

melody = \fixed c'' {
  \tempo 4 = 120
  a,4 c e c   | f, a, c a,   | e, g, c g, | d, g, b, d  |
}

harmony = \chordmode { a1:m | f | c | g }

\score {
  <<
    \new ChordNames \harmony
    \new Staff \with { midiInstrument = "vibraphone" } \melody
  >>
  \layout { }
  \midi { }
}
