// The pad: one chord per bar, Am - F - C - G, at 120 BPM (2 s a bar).
//
//   sclang pad.scd           play live (needs host-audio+jack)
//   sclang pad.scd render    write out/pad.wav instead, no audio server

var chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
var bar = 2.0;
var render = thisProcess.argv.includesEqual("render");

var def = SynthDef(\pad, { |freq = 220, amp = 0.04, dur = 2|
    var env = EnvGen.kr(Env.linen(0.3, dur - 0.6, 0.3), doneAction: 2);
    var sig = Mix(Saw.ar(freq * [0.995, 1, 1.005])) * amp * env;
    Out.ar(0, LPF.ar(sig, 1400) ! 2);
});

var events = chords.collect { |chord, i|
    chord.collect { |note| [i * bar, [\s_new, \pad, -1, 0, 0, \freq, note.midicps, \dur, bar]] }
}.flatten(1);

if (render) {
    Score([[0.0, [\d_recv, def.asBytes]]] ++ events ++ [[chords.size * bar + 0.5, [\c_set, 0, 0]]])
    .recordNRT(
        outputFilePath: File.getcwd +/+ "out/pad.wav",
        headerFormat: "WAV", sampleFormat: "int16",
        options: ServerOptions.new.numOutputBusChannels_(2),
        duration: chords.size * bar + 0.5,
        action: { "pad: wrote out/pad.wav".postln; 0.exit }
    );
} {
    s.options.numInputBusChannels = 0;
    s.waitForBoot {
        def.add;
        s.sync;
        Score(events).play(s);
        (chords.size * bar + 0.5).wait;
        0.exit;
    };
};
