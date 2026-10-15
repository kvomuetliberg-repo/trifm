// TriFM — Mac test patch (no norns needed)
//
// Same SynthDef as the norns engine (lib/Engine_TriFM.sc), with a
// slider window and a clock that fires the envelopes, so you can hear
// and tweak the engine in SuperCollider on your Mac.
//
// HOW TO RUN
// 1. Install SuperCollider (supercollider.github.io) and open this file
//    in the SuperCollider app (not a text editor).
// 2. Press Cmd+A (select all), then Cmd+Return.
// 3. Watch the Post window (bottom right). After a few seconds it says
//    "TriFM: ready" and a window with sliders opens.
// 4. Press Cmd+. to stop all sound.
// A connected MIDI keyboard also plays the voice.

(
"TriFM: starting the audio server...".postln;
// No audio input is needed. Turning inputs off avoids the common macOS
// boot error "Mismatched sample rates" (e.g. with Bluetooth headphones).
s.options.numInputBusChannels = 0;
s.options.sampleRate = nil;
s.waitForBoot({
	var ratios = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16];
	var algNames = ["3>2>1", "2+3>1", "3>1+2", "2>1 | 3", "3>2>1+2", "triangle", "1|2|3", "loop"];
	var divNames = ["1/32", "1/24", "1/16", "1/12", "1/8", "1/6", "1/4", "1/2", "1/1", "2/1"];
	var divBeats = [1/8, 1/6, 1/4, 1/3, 1/2, 2/3, 1, 2, 4, 8];
	var scaleNames = [\major, \minor, \dorian, \phrygian, \lydian, \minorPentatonic, \majorPentatonic, \whole, \chromatic];
	var opRatio = [3, 5, 7];      // 0-based index into ratios -> 1, 2, 3
	var opFine = [0, 0, 0];
	var win, view, layout, row, popRow, header, sendRatio;

	// --- BEGIN SYNTHDEF ---
	SynthDef(\triFM, {
		var trig = \t_trig.tr(0);
		var hz = Lag.kr(\hz.kr(110), \glide.kr(0));
		var alg = \alg.kr(0).round.clip(0, 7);
	
		// routing per algorithm (index = alg)
		//            0      1      2      3      4      5      6      7
		//          3>2>1  2+3>1  3>1+2  2>1|3  3>2>1+2  tri   1|2|3   loop
		var m32 = Select.kr(alg, [1, 0, 1, 0, 1, 1, 0, 1]);
		var m31 = Select.kr(alg, [0, 1, 1, 0, 0, 1, 0, 0]);
		var m21 = Select.kr(alg, [1, 1, 0, 1, 1, 1, 0, 1]);
		var m13 = Select.kr(alg, [0, 0, 0, 0, 0, 0, 0, 1]);
		var c1  = Select.kr(alg, [1, 1, 1, 1, 1, 1, 1, 1]);
		var c2  = Select.kr(alg, [0, 0, 1, 0, 1, 0, 1, 0]);
		var c3  = Select.kr(alg, [0, 0, 0, 1, 0, 0, 1, 0]);
	
		var ratio = [\r1.kr(1), \r2.kr(2), \r3.kr(3)];
		var depth = [\depth1.kr(0), \depth2.kr(2), \depth3.kr(3)];
		var atk = [\atk1.kr(0.005), \atk2.kr(0.005), \atk3.kr(0.005)];
		var dec = [\dec1.kr(0.6), \dec2.kr(0.3), \dec3.kr(0.15)];
		var crv = [\curve1.kr(-4), \curve2.kr(-4), \curve3.kr(-4)];
		var amt = [\envamt1.kr(1), \envamt2.kr(1), \envamt3.kr(1)];
	
		// per-operator envelope, shaped by env amount (0..1)
		var env = 3.collect { |i|
			var e = EnvGen.ar(Env.perc(atk[i], dec[i], 1, crv[i]), trig);
			(1 - amt[i]) + (amt[i] * e)
		};
		var freq = ratio * hz;
	
		var loopIn = LocalIn.ar(1);
		var s1, s2, s3, sig, fe, cut, res;
	
		// op3: self feedback; in loop algorithm op1 modulates its frequency
		s3 = SinOscFB.ar(
			freq[2] * (1 + (m13 * loopIn * depth[0] * 0.25)),
			\fb.kr(0)
		) * env[2];
		// op2: phase modulated by op3
		s2 = SinOsc.ar(freq[1], (m32 * s3 * depth[2]).mod(2pi)) * env[1];
		// op1: phase modulated by op3 and op2
		s1 = SinOsc.ar(freq[0], ((m31 * s3 * depth[2]) + (m21 * s2 * depth[1])).mod(2pi)) * env[0];
		LocalOut.ar(s1);
	
		// carrier mix, normalised by number of carriers
		sig = ((s1 * c1) + (s2 * c2) + (s3 * c3)) / (c1 + c2 + c3).max(1);
	
		// drive + low-pass filter with envelope and keytracking
		fe = EnvGen.kr(Env.perc(\fatk.kr(0.005), \fdec.kr(0.4), 1, -4), trig);
		cut = \cutoff.kr(2000) * (2 ** (\fenv.kr(0) * fe)) * ((hz / 261.63) ** \ktrack.kr(0));
		cut = cut.clip(20, 18000);
		res = \res.kr(0.2).clip(0, 1);
		sig = (sig * \drive.kr(1)).tanh;
		sig = MoogFF.ar(sig, cut, res * 3.9) * (1 + res);
	
		sig = LeakDC.ar(sig) * \amp.kr(0.5);
		sig = Limiter.ar(sig, 0.95, 0.005);
		Out.ar(\out.ir(0), Pan2.ar(sig, \pan.kr(0)));
	}).add;
	// --- END SYNTHDEF ---

	s.sync;
	~fm = Synth(\triFM);

	~running = true;
	~div = 0.25;
	~prob = 100;
	~root = 48;
	~scale = Scale.major;
	~spread = 7;

	~trig = { |note|
		note = note ?? { ~root + ~scale.performDegreeToKey((~spread + 1).rand) };
		~fm.set(\hz, note.midicps, \t_trig, 1);
	};

	~clock = TempoClock(110 / 60);
	~player = Routine {
		loop {
			if(~running and: { 100.rand < ~prob }) { ~trig.value };
			~div.wait;
		}
	}.play(~clock);

	// MIDI keyboard input (optional; skipped quietly if MIDI is unavailable)
	try {
		MIDIClient.init;
		MIDIIn.connectAll;
		MIDIdef.noteOn(\triFMnote, { |vel, note| ~trig.value(note) });
	} { "TriFM: MIDI not available, continuing without it".postln };

	sendRatio = { |i|
		~fm.set(("r" ++ (i + 1)).asSymbol, ratios[opRatio[i]] * (2 ** (opFine[i] / 1200)));
	};

	// --- GUI helpers ---
	row = { |label, spec, init, action|
		var nb = NumberBox().maxWidth_(70).decimals_(3);
		var sl = Slider().orientation_(\horizontal);
		sl.value = spec.unmap(init);
		nb.value = init;
		sl.action = { |v| var x = spec.map(v.value); nb.value = x; action.(x) };
		nb.action = { |n| var x = spec.constrain(n.value); sl.value = spec.unmap(x); action.(x) };
		action.(init);
		HLayout(StaticText().string_(label).minWidth_(100), [sl, stretch: 1], nb)
	};
	popRow = { |label, items, init, action|
		var pm = PopUpMenu().items_(items).value_(init);
		pm.action = { |m| action.(m.value) };
		action.(init);
		HLayout(StaticText().string_(label).minWidth_(100), [pm, stretch: 1])
	};
	header = { |txt| StaticText().string_(txt).font_(Font.default.copy.bold_(true)) };

	win = Window("TriFM test", Rect(100, 100, 520, 820));
	view = ScrollView(win).hasHorizontalScroller_(false);
	win.layout = VLayout(view);
	layout = VLayout(
		HLayout(
			Button().states_([["trigger"]]).action_({ ~trig.value }),
			Button().states_([["clock running"], ["clock stopped"]]).action_({ |b| ~running = b.value == 0 })
		),
		header.("MAIN"),
		popRow.("algorithm", algNames, 0, { |v| ~fm.set(\alg, v) }),
		popRow.("clock division", divNames, 2, { |v| ~div = divBeats[v] }),
		row.("tempo (bpm)", ControlSpec(20, 300, \lin, 1), 110, { |v| ~clock.tempo = v / 60 }),
		row.("probability %", ControlSpec(0, 100, \lin, 1), 100, { |v| ~prob = v }),
		row.("root note", ControlSpec(24, 84, \lin, 1), 48, { |v| ~root = v }),
		popRow.("scale", scaleNames.collect(_.asString), 0, { |v| ~scale = Scale.at(scaleNames[v]) }),
		row.("pitch spread", ControlSpec(0, 24, \lin, 1), 7, { |v| ~spread = v.asInteger }),
		row.("glide", ControlSpec(0, 2, \lin), 0, { |v| ~fm.set(\glide, v) })
	);
	[
		[0, 3, 0, 0.6, 0.005],   // op, ratio index (0-based), depth, attack, decay defaults
		[1, 5, 2, 0.3, 0.005],
		[2, 7, 3, 0.15, 0.005]
	].do { |d|
		var i = d[0], n = i + 1;
		opRatio[i] = d[1];
		layout.add(header.("OPERATOR " ++ n));
		layout.add(popRow.("ratio", ratios.collect(_.asString), d[1], { |v| opRatio[i] = v; sendRatio.(i) }));
		layout.add(row.("fine (cents)", ControlSpec(-100, 100, \lin, 1), 0, { |v| opFine[i] = v; sendRatio.(i) }));
		layout.add(row.("fm depth", ControlSpec(0, 12, \lin), d[2], { |v| ~fm.set(("depth" ++ n).asSymbol, v) }));
		layout.add(row.("attack", ControlSpec(0.001, 4, \exp), d[4], { |v| ~fm.set(("atk" ++ n).asSymbol, v) }));
		layout.add(row.("decay", ControlSpec(0.01, 8, \exp), d[3], { |v| ~fm.set(("dec" ++ n).asSymbol, v) }));
		layout.add(row.("curve", ControlSpec(-8, 8, \lin, 0.5), -4, { |v| ~fm.set(("curve" ++ n).asSymbol, v) }));
		layout.add(row.("env amount", ControlSpec(0, 1, \lin), 1, { |v| ~fm.set(("envamt" ++ n).asSymbol, v) }));
	};
	layout.add(row.("op3 feedback", ControlSpec(0, 3, \lin), 0, { |v| ~fm.set(\fb, v) }));
	[
		header.("FILTER / OUT"),
		row.("cutoff", ControlSpec(20, 18000, \exp), 2000, { |v| ~fm.set(\cutoff, v) }),
		row.("resonance", ControlSpec(0, 1, \lin), 0.2, { |v| ~fm.set(\res, v) }),
		row.("drive", ControlSpec(0.5, 10, \exp), 1, { |v| ~fm.set(\drive, v) }),
		row.("filter env (oct)", ControlSpec(-4, 6, \lin), 2, { |v| ~fm.set(\fenv, v) }),
		row.("filter attack", ControlSpec(0.001, 4, \exp), 0.005, { |v| ~fm.set(\fatk, v) }),
		row.("filter decay", ControlSpec(0.01, 8, \exp), 0.3, { |v| ~fm.set(\fdec, v) }),
		row.("keytrack", ControlSpec(0, 1, \lin), 0.5, { |v| ~fm.set(\ktrack, v) }),
		row.("level", ControlSpec(0, 1, \lin), 0.6, { |v| ~fm.set(\amp, v) }),
		row.("pan", ControlSpec(-1, 1, \lin), 0, { |v| ~fm.set(\pan, v) })
	].do { |item| layout.add(item) };

	view.canvas = View().layout_(layout);
	win.onClose = { ~player.stop; ~fm.free; MIDIdef.all[\triFMnote] !? _.free };
	win.front;
	"TriFM: ready - the window is open and the clock is running.".postln;
}, onFailure: {
	"TriFM: the audio server did not start. Look at the red lines above in the Post window.".postln;
});
)
