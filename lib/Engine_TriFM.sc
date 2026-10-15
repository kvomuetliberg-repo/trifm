// Engine_TriFM
// 3-operator FM voice for norns
//
// op3 -> op2 -> op1 are computed in that order, so forward modulation
// (3>2, 3>1, 2>1) is sample-accurate. op3 has true one-sample self
// feedback (SinOscFB). The "loop" algorithm sends op1 back into op3's
// frequency through LocalIn (one control block of delay) - gritty by design.
//
// Each operator: ratio, fm depth (modulation index in radians),
// AD envelope (attack, decay, curve) retriggered by \t_trig,
// env amount (0 = static level, 1 = fully enveloped).
// Post: drive (tanh) -> MoogFF low-pass with cutoff, resonance,
// filter envelope (in octaves) and keytracking.

Engine_TriFM : CroneEngine {
	var <synth;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
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

		context.server.sync;

		synth = Synth.new(\triFM, [\out, context.out_b.index], context.xg);

		// one float command per synth control
		[
			\alg, \hz, \glide,
			\r1, \r2, \r3,
			\depth1, \depth2, \depth3,
			\atk1, \atk2, \atk3,
			\dec1, \dec2, \dec3,
			\curve1, \curve2, \curve3,
			\envamt1, \envamt2, \envamt3,
			\fb, \cutoff, \res, \drive, \fenv, \fatk, \fdec, \ktrack,
			\amp, \pan
		].do { |key|
			this.addCommand(key.asString, "f", { arg msg;
				synth.set(key, msg[1]);
			});
		};

		// set pitch and fire all envelopes
		this.addCommand("trig", "f", { arg msg;
			synth.set(\hz, msg[1], \t_trig, 1);
		});
	}

	free {
		synth.free;
	}
}
