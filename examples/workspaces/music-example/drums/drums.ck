// The drums: kick, snare and hi-hat, each made from an oscillator or noise.
// 16 steps per bar: x = hit, o = accent, . = rest. Edit and run `just drums`.
//
//   chuck drums.ck           play live
//   chuck drums.ck:render    write out/drums.wav instead (use with --silent)

"x.....x...x....." => string KICK;
"....x.......x..o" => string SNARE;
"x.x.x.x.x.x.x.xo" => string HAT;

120 => float BPM;
4   => int BARS;
(60.0 / BPM / 4)::second => dur STEP;

Gain master => dac;
0.8 => master.gain;

WvOut2 rec;
me.args() > 0 && me.arg(0) == "render" => int rendering;
if (rendering) {
    dac => rec => blackhole;
    "out/drums.wav" => rec.wavFilename;
}

// A sine whose pitch falls fast: the thump.
fun void kick(float g) {
    SinOsc s => ADSR e => master;
    g => s.gain;
    e.set(1::ms, 300::ms, 0, 1::ms);
    e.keyOn();
    now => time start;
    while (now - start < 300::ms) {
        (now - start) / 1::second => float t;
        45 + 110 * Math.exp(-t * 30) => s.freq;
        1::ms => now;
    }
    s =< e; e =< master;
}

// A short tone plus band-passed noise.
fun void snare(float g) {
    Noise n => BPF f => ADSR e => master;
    SinOsc s => e;
    f.set(1800, 1);
    g * 0.9 => n.gain;
    g * 0.3 => s.gain;
    185 => s.freq;
    e.set(1::ms, 150::ms, 0, 1::ms);
    e.keyOn();
    160::ms => now;
    n =< f; s =< e; e =< master;
}

// High-passed noise; an accent rings longer, like a half-open hat.
fun void hat(float g, dur decay) {
    Noise n => HPF h => ADSR e => master;
    7000 => h.freq;
    g => n.gain;
    e.set(1::ms, decay, 0, 1::ms);
    e.keyOn();
    decay + 10::ms => now;
    n =< h; e =< master;
}

fun int hit(string pattern, int step) {
    pattern.charAt(step) => int c;
    if (c == "x".charAt(0)) return 1;
    if (c == "o".charAt(0)) return 2;
    return 0;
}

for (0 => int bar; bar < BARS; bar++) {
    for (0 => int step; step < 16; step++) {
        hit(KICK, step)  => int k;
        hit(SNARE, step) => int s;
        hit(HAT, step)   => int h;
        if (k > 0) spork ~ kick(0.9);
        if (s > 0) spork ~ snare(s == 2 ? 0.8 : 0.5);
        if (h == 1) spork ~ hat(0.15, 40::ms);
        if (h == 2) spork ~ hat(0.2, 120::ms);
        STEP => now;
    }
}
500::ms => now;

if (rendering) rec.closeFile();
