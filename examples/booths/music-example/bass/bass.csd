<CsoundSynthesizer>
; The bass: eighth notes on the chord roots, Am - F - C - G, at 120 BPM.
;
;   csound -odac bass.csd              play live (ALSA default -> host-audio)
;   csound -o out/bass.wav bass.csd    render to a file
<CsOptions>
-d -m0
</CsOptions>
<CsInstruments>
sr     = 44100
ksmps  = 32
nchnls = 2
0dbfs  = 1

; The sequencer: one root per bar, an octave/fifth pattern per eighth note.
instr 1
  iRoots[] fillarray 45, 41, 48, 43
  iSteps[] fillarray 0, 0, 12, 0, 0, 12, 0, 7
  iBar = 0
  while iBar < 4 do
    iStep = 0
    while iStep < 8 do
      schedule 2, iBar * 2 + iStep * 0.25, 0.22, iRoots[iBar] + iSteps[iStep]
      iStep += 1
    od
    iBar += 1
  od
endin

; The voice: a sawtooth through a Moog-style filter that closes as the note decays.
instr 2
  kEnv  expseg 1, p3, 0.01
  aSaw  vco2 0.35, cpsmidinn(p4)
  aOut  moogladder aSaw, 200 + 1600 * kEnv, 0.4
  aOut  = aOut * linseg(0, 0.005, 1, p3 - 0.01, 1, 0.005, 0)
  outs aOut, aOut
endin
</CsInstruments>
<CsScore>
i 1 0 0.01
f 0 8.5
</CsScore>
</CsoundSynthesizer>
