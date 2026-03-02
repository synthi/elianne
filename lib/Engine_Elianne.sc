// lib/Engine_Elianne.sc v0.400 (MASTER DSP ARCHITECTURE - THE LIVING CORE)
// CHANGELOG v0.400:
// 1. PHYSICS: Inyección de Pink/Brown noise en el núcleo de los waveshapers (Cycle-to-cycle jitter).
// 2. PHYSICS: Curva polinómica de 8º grado para la ruptura de resonancia del 1047 (Solo satura a Q > 400).
// 3. DSP: Generación de dos Wavetables Piecewise (Node y Master) para emulación CA3080 exacta.
// 4. FIX: Estabilidad absoluta garantizada con System Age = 0.

Engine_Elianne : CroneEngine {
    var <bus_nodes_tx;
    var <bus_nodes_rx;
    var <bus_levels;
    var <bus_pans;
    var <bus_physics;
    
    var <synth_matrix_amps;
    var <synth_matrix_rows;
    var <synth_mods;
    var <synth_adc;
    var matrix_state;
    
    var ca3080_node_buf;
    var ca3080_master_buf;
    
    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        var wt_node, wt_master;
        
        bus_nodes_tx = Bus.audio(context.server, 64);
        bus_nodes_rx = Bus.audio(context.server, 64);
        bus_levels = Bus.control(context.server, 64);
        bus_pans = Bus.control(context.server, 64);
        bus_physics = Bus.control(context.server, 10);
        
        64.do { |i| bus_levels.setAt(i, 0.33) };
        
        synth_mods = Array.newClear(8);
        synth_matrix_rows = Array.newClear(64);
        matrix_state = Array.fill(64, { Array.fill(64, 0.0) });

        // WAVETABLE 1: Nodos (Transparente hasta 0.6, compresión suave, saturación en picos)
        wt_node = Signal.fill(1024, { |i|
            var x = i.linlin(0, 1023, -1.0, 1.0);
            var sign = x.sign;
            var absX = x.abs;
            var y = if(absX <= 0.6) {
                absX;
            } {
                0.6 + (tanh((absX - 0.6) * 2.0) * 0.35);
            };
            y * sign;
        });
        ca3080_node_buf = Buffer.loadCollection(context.server, wt_node.asWavetable);

        // WAVETABLE 2: Master (Transparente hasta 0.8, compresión densa hasta 0.99)
        wt_master = Signal.fill(1024, { |i|
            var x = i.linlin(0, 1023, -1.0, 1.0);
            var sign = x.sign;
            var absX = x.abs;
            var y = if(absX <= 0.8) {
                absX;
            } {
                0.8 + (tanh((absX - 0.8) * 3.0) * 0.19);
            };
            y * sign;
        });
        ca3080_master_buf = Buffer.loadCollection(context.server, wt_master.asWavetable);

        context.server.sync;

        OSCFunc({ |msg|
            NetAddr("127.0.0.1", 10111).sendMsg("/elianne_levels", *msg.drop(3));
        }, '/elianne_levels', context.server.addr).fix;

        SynthDef(\Elianne_MatrixAmps, {
            var tx = InFeedback.ar(bus_nodes_tx.index, 64);
            var amps = Amplitude.kr(tx, 0.05, 0.1);
            SendReply.kr(Impulse.kr(15), '/elianne_levels', amps);
        }).add;

        SynthDef(\Elianne_MatrixRow, { arg out_bus;
            var tx = InFeedback.ar(bus_nodes_tx.index, 64);
            var gains = NamedControl.kr(\gains, 0 ! 64);
            var sum = (tx * gains).sum;
            Out.ar(out_bus, sum);
        }).add;

        SynthDef(\Elianne_ADC, {
            arg out_l, out_r, lvl_l, lvl_r, shaper_buf;
            var adc = SoundIn.ar([0, 1]);
            var sig_l = Shaper.ar(shaper_buf, (adc[0] * In.kr(lvl_l)).clip(-1.0, 1.0));
            var sig_r = Shaper.ar(shaper_buf, (adc[1] * In.kr(lvl_r)).clip(-1.0, 1.0));
            Out.ar(out_l, sig_l);
            Out.ar(out_r, sig_r);
        }).add;

        // =====================================================================
        // SYNTH 1 & 2: ARP 1004-P (THE LIVING CORE)
        // =====================================================================
        SynthDef(\Elianne_1004T, {
            arg in_fm1, in_fm2, in_pwm, in_voct,
                out_main, out_inv, out_sine, out_pulse,
                lvl_fm1, lvl_fm2, lvl_pwm, lvl_voct,
                lvl_main, lvl_inv, lvl_sine, lvl_pulse,
                tune=100.0, fine=0.0, pwm_base=0.5,
                mix_sine=1.0, mix_tri=0.0, mix_saw=0.0, mix_pulse=0.0,
                range=0, fm1_type=0, fm2_type=1, phys_bus, seed_offset=0, shaper_buf;
                
            var sys_age, slew_time;
            var pink_cv, brown_cv, pink_core, brown_core;
            var fm1, fm2, pwm_mod, voct;
            var fm1_lin, fm1_exp, fm2_lin, fm2_exp;
            var age_pitch, age_amp;
            var base_freq, freq, pwm_final, phase;
            var raw_tri, sqr, sig_tri, sig_saw, sig_pulse, sig_sine, mix;
            
            sys_age = In.kr(phys_bus + 0) * 10.0; 
            slew_time = 0.001 + (sys_age * 0.005); 
            
            // Ruido Dual
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            brown_cv = LeakDC.ar(BrownNoise.ar(0.0005 * (1.0 + (sys_age * 2.0))), 0.99);
            
            pink_core = PinkNoise.ar(0.0005 * (1.0 + (sys_age * 5.0)));
            brown_core = LeakDC.ar(BrownNoise.ar(0.001 * (1.0 + (sys_age * 5.0))), 0.99);
            
            fm1 = Lag.ar(InFeedback.ar(in_fm1) * In.kr(lvl_fm1) + pink_cv, slew_time);
            fm2 = Lag.ar(InFeedback.ar(in_fm2) * In.kr(lvl_fm2) + pink_cv, slew_time);
            pwm_mod = Lag.ar(InFeedback.ar(in_pwm) * In.kr(lvl_pwm) + pink_cv, slew_time);
            voct = Lag.ar(InFeedback.ar(in_voct) * In.kr(lvl_voct) + pink_cv, slew_time); 
            
            voct = voct * (1.0 - (voct.abs * 0.01 * (1.0 + sys_age)));
            
            fm1_lin = fm1 * 1000.0 * (1 - fm1_type); 
            fm1_exp = fm1 * 5.0 * fm1_type;          
            fm2_lin = fm2 * 1000.0 * (1 - fm2_type);
            fm2_exp = fm2 * 5.0 * fm2_type;
            
            age_pitch = K2A.ar(LFNoise2.kr(0.0113 + seed_offset)) * sys_age * 0.002;
            age_amp = 1.0 - (K2A.ar(LFNoise2.kr(0.0233 + seed_offset)).range(0, 0.1) * sys_age);
            
            base_freq = Select.kr(range,[tune, tune * 0.001]);
            
            // Deriva térmica inyectada en el exponente
            freq = (K2A.ar(base_freq + fine) + fm1_lin + fm2_lin) * (2.0 ** (voct * 5.0 + age_pitch + fm1_exp + fm2_exp + brown_cv));
            
            // Jitter en el comparador PWM
            pwm_final = (pwm_base + pwm_mod + pink_core).clip(0.0, 1.0);
            
            phase = Phasor.ar(0, freq * SampleDur.ir, 0, 1);
            
            // Inyección de ruido en el núcleo geométrico (Cycle-to-cycle jitter)
            raw_tri = (phase * 2 - 1).abs * 2 - 1 + pink_core + brown_core; 
            sqr = (phase > 0.5) * 2 - 1;
            
            sig_tri = LeakDC.ar(raw_tri + 0.015);
            sig_saw = (phase * 2 - 1) + (HPF.ar(Impulse.ar(freq), 10000) * 0.1) + pink_core;
            sig_pulse = (sig_tri > ((pwm_final * 2) - 1)) * 2 - 1;
            
            // El ruido inyectado en sig_tri se distorsiona no linealmente aquí
            sig_sine = (LeakDC.ar(sig_tri - (sig_tri.pow(3) / 6.0)) + (sqr * 0.02)) * 1.2;
            
            mix = ((sig_sine * mix_sine) + (sig_tri * mix_tri) + (sig_saw * mix_saw) + (sig_pulse * mix_pulse)) * age_amp;
            
            mix = CrossoverDistortion.ar(mix, 0.01, 0.01);
            sig_tri = CrossoverDistortion.ar(sig_tri, 0.01, 0.01);
            sig_sine = CrossoverDistortion.ar(sig_sine, 0.01, 0.01);
            sig_pulse = CrossoverDistortion.ar(sig_pulse, 0.01, 0.01);
            
            // CA3080 Node Shaper en las salidas
            Out.ar(out_main, Shaper.ar(shaper_buf, mix.clip(-1.0, 1.0)) * In.kr(lvl_main));
            Out.ar(out_inv, Shaper.ar(shaper_buf, sig_tri.clip(-1.0, 1.0)) * In.kr(lvl_inv)); 
            Out.ar(out_sine, Shaper.ar(shaper_buf, sig_sine.clip(-1.0, 1.0)) * In.kr(lvl_sine));
            Out.ar(out_pulse, Shaper.ar(shaper_buf, sig_pulse.clip(-1.0, 1.0)) * In.kr(lvl_pulse));
        }).add;

        // =====================================================================
        // SYNTH 3: ARP 1023 (THE LIVING CORE)
        // =====================================================================
        SynthDef(\Elianne_1023, {
            arg in_fm1, in_fm2, in_pv1, in_pv2,
                out_o1, out_o2, out_i1, out_i2,
                lvl_fm1, lvl_fm2, lvl_pv1, lvl_pv2,
                lvl_o1, lvl_o2, lvl_i1, lvl_i2,
                tune1=100, pwm1=0.5, morph1=0, range1=0, pv1_mode=0, fm1_mode=0,
                tune2=101, pwm2=0.5, morph2=0, range2=0, pv2_mode=0, fm2_mode=0,
                out3_wave=0, out4_wave=0, phys_bus, shaper_buf;
                
            var sys_age, slew_time;
            var pink_cv, brown_cv, pink_core, brown_core;
            var age_p1, age_a1, age_p2, age_a2;
            var fm1_in, fm1_pitch, fm1_morph, pv1, voct1, pwm_mod1, freq1, ph1, rtri1, sqr1, tri1, saw1, pul1, sin1, waves1, mix1, sig_out3;
            var fm2_in, fm2_pitch, fm2_morph, pv2, voct2, pwm_mod2, freq2, ph2, rtri2, sqr2, tri2, saw2, pul2, sin2, waves2, mix2, sig_out4;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            slew_time = 0.001 + (sys_age * 0.005);
            
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            brown_cv = LeakDC.ar(BrownNoise.ar(0.0005 * (1.0 + (sys_age * 2.0))), 0.99);
            pink_core = PinkNoise.ar(0.0005 * (1.0 + (sys_age * 5.0)));
            brown_core = LeakDC.ar(BrownNoise.ar(0.001 * (1.0 + (sys_age * 5.0))), 0.99);
            
            age_p1 = K2A.ar(LFNoise2.kr(0.0127)) * sys_age * 0.002;
            age_a1 = 1.0 - (K2A.ar(LFNoise2.kr(0.0241)).range(0, 0.1) * sys_age);
            age_p2 = K2A.ar(LFNoise2.kr(0.0139)) * sys_age * 0.002;
            age_a2 = 1.0 - (K2A.ar(LFNoise2.kr(0.0257)).range(0, 0.1) * sys_age);
            
            // VCO 1
            fm1_in = Lag.ar(InFeedback.ar(in_fm1) * In.kr(lvl_fm1) + pink_cv, slew_time);
            fm1_pitch = fm1_in * (1 - fm1_mode) * 1000.0; 
            fm1_morph = fm1_in * fm1_mode * 5.0;
            
            pv1 = Lag.ar(InFeedback.ar(in_pv1) * In.kr(lvl_pv1) + pink_cv, slew_time); 
            pv1 = pv1 * (1.0 - (pv1.abs * 0.01 * (1.0 + sys_age))); 
            voct1 = pv1 * pv1_mode * 5.0;
            pwm_mod1 = pv1 * (1 - pv1_mode);
            
            freq1 = (K2A.ar(Select.kr(range1,[tune1, tune1*0.001])) + fm1_pitch) * (2.0 ** (voct1 + age_p1 + brown_cv));
            
            ph1 = Phasor.ar(0, freq1 * SampleDur.ir, 0, 1);
            rtri1 = (ph1 * 2 - 1).abs * 2 - 1 + pink_core + brown_core;
            sqr1 = (ph1 > 0.5) * 2 - 1;
            tri1 = LeakDC.ar(rtri1 + 0.015);
            saw1 = (ph1 * 2 - 1) + (HPF.ar(Impulse.ar(freq1), 10000) * 0.1) + pink_core;
            pul1 = (tri1 > (((pwm1 + pwm_mod1 + pink_core).clip(0.0, 1.0) * 2) - 1)) * 2 - 1;
            sin1 = (LeakDC.ar(tri1 - (tri1.pow(3) / 6.0)) + (sqr1 * 0.02)) * 1.2;
            
            waves1 =[sin1, tri1, saw1, sqr1, pul1, sin1.neg, tri1, saw1.neg, sqr1, pul1.neg];
            mix1 = SelectX.ar((morph1 + fm1_morph + brown_core).clip(0,1) * 9.0, waves1) * age_a1;
            sig_out3 = Select.ar(out3_wave,[sin1, tri1, saw1, sqr1, pul1]);
            
            // VCO 2
            fm2_in = Lag.ar(InFeedback.ar(in_fm2) * In.kr(lvl_fm2) + pink_cv, slew_time);
            fm2_pitch = fm2_in * (1 - fm2_mode) * 1000.0;
            fm2_morph = fm2_in * fm2_mode * 5.0;
            
            pv2 = Lag.ar(InFeedback.ar(in_pv2) * In.kr(lvl_pv2) + pink_cv, slew_time);
            pv2 = pv2 * (1.0 - (pv2.abs * 0.01 * (1.0 + sys_age))); 
            voct2 = pv2 * pv2_mode * 5.0;
            pwm_mod2 = pv2 * (1 - pv2_mode);
            
            freq2 = (K2A.ar(Select.kr(range2,[tune2, tune2*0.001])) + fm2_pitch) * (2.0 ** (voct2 + age_p2 + brown_cv));
            
            ph2 = Phasor.ar(0, freq2 * SampleDur.ir, 0, 1);
            rtri2 = (ph2 * 2 - 1).abs * 2 - 1 + pink_core + brown_core;
            sqr2 = (ph2 > 0.5) * 2 - 1;
            tri2 = LeakDC.ar(rtri2 + 0.015);
            saw2 = (ph2 * 2 - 1) + (HPF.ar(Impulse.ar(freq2), 10000) * 0.1) + pink_core;
            pul2 = (tri2 > (((pwm2 + pwm_mod2 + pink_core).clip(0.0, 1.0) * 2) - 1)) * 2 - 1;
            sin2 = (LeakDC.ar(tri2 - (tri2.pow(3) / 6.0)) + (sqr2 * 0.02)) * 1.2;
            
            waves2 =[sin2, tri2, saw2, sqr2, pul2, sin2.neg, tri2, saw2.neg, sqr2, pul2.neg];
            mix2 = SelectX.ar((morph2 + fm2_morph + brown_core).clip(0,1) * 9.0, waves2) * age_a2;
            sig_out4 = Select.ar(out4_wave,[sin2, tri2, saw2, sqr2, pul2]);
            
            mix1 = CrossoverDistortion.ar(mix1, 0.01, 0.01);
            mix2 = CrossoverDistortion.ar(mix2, 0.01, 0.01);
            sig_out3 = CrossoverDistortion.ar(sig_out3, 0.01, 0.01);
            sig_out4 = CrossoverDistortion.ar(sig_out4, 0.01, 0.01);
            
            Out.ar(out_o1, Shaper.ar(shaper_buf, mix1.clip(-1.0, 1.0)) * In.kr(lvl_o1));
            Out.ar(out_o2, Shaper.ar(shaper_buf, mix2.clip(-1.0, 1.0)) * In.kr(lvl_o2));
            Out.ar(out_i1, Shaper.ar(shaper_buf, sig_out3.clip(-1.0, 1.0)) * In.kr(lvl_i1)); 
            Out.ar(out_i2, Shaper.ar(shaper_buf, sig_out4.clip(-1.0, 1.0)) * In.kr(lvl_i2)); 
        }).add;

        // =====================================================================
        // SYNTH 4: ARP 1016/36
        // =====================================================================
        SynthDef(\Elianne_1016, {
            arg in_sig, in_clk, out_n1, out_n2, out_slow, out_step,
                lvl_sig, lvl_clk, lvl_n1, lvl_n2, lvl_slow, lvl_step,
                slow_rate=0.1, tilt1=0, tilt2=0, type1=0, type2=1,
                clk_rate=2.0, prob_skew=0, glide=0, clk_thresh=0.1, phys_bus, shaper_buf;
                
            var sys_age, pink_cv;
            var sig, clk_ext, droop_amt;
            var n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit;
            var noise1, noise2, clk_int, clk_trig;
            var sh_src, rand_val, skewed, droop_env, step_out, slow_out;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            
            sig = InFeedback.ar(in_sig) * In.kr(lvl_sig) + pink_cv;
            clk_ext = InFeedback.ar(in_clk) * In.kr(lvl_clk) + pink_cv; 
            droop_amt = In.kr(phys_bus + 1);
            
            n_pink = PinkNoise.ar;
            n_white = WhiteNoise.ar * 0.5;
            n_crackle = Crackle.ar(1.9);
            n_rain = Dust2.ar(LFNoise1.kr(0.3).exprange(300, 2000)) * 0.9;
            n_lorenz = LFNoise1.ar(500) * 0.7;
            n_grit = Latch.ar(WhiteNoise.ar, Dust.ar(50)) * 0.4;
            
            noise1 = Select.ar(type1,[n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit]);
            noise2 = Select.ar(type2,[n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit]);
            
            clk_int = Impulse.ar(clk_rate);
            clk_trig = clk_int + Schmidt.ar(clk_ext, clk_thresh, clk_thresh + 0.1);
            
            noise1 = BLowShelf.ar(noise1, 1000, 1.0, tilt1 * -12.0);
            noise1 = BHiShelf.ar(noise1, 1000, 1.0, tilt1 * 12.0);
            
            noise2 = BLowShelf.ar(noise2, 1000, 1.0, tilt2 * -12.0);
            noise2 = BHiShelf.ar(noise2, 1000, 1.0, tilt2 * 12.0);
            
            sh_src = Select.ar(sig > 0.001,[noise1, sig]); 
            
            rand_val = Latch.ar(sh_src, clk_trig);
            skewed = rand_val.sign * (rand_val.abs ** (2.0 ** prob_skew.neg));
            
            droop_env = EnvGen.ar(Env([1, 0],[10]), clk_trig);
            
            step_out = LagUD.ar(skewed * (1.0 - (droop_amt * (1.0 - droop_env))), 0.001, 0.01 + glide);
            
            slow_out = LFNoise2.ar(slow_rate);
            slow_out = slow_out.sign * (slow_out.abs ** (2.0 ** prob_skew.neg));
            
            step_out = (step_out * 2.5).softclip;
            slow_out = (slow_out * 2.5).softclip;
            noise1 = (noise1 * 2.0).softclip;
            noise2 = (noise2 * 2.0).softclip;
            
            Out.ar(out_n1, Shaper.ar(shaper_buf, noise1) * In.kr(lvl_n1));
            Out.ar(out_n2, Shaper.ar(shaper_buf, noise2) * In.kr(lvl_n2));
            Out.ar(out_slow, Shaper.ar(shaper_buf, slow_out) * In.kr(lvl_slow));
            Out.ar(out_step, Shaper.ar(shaper_buf, step_out) * In.kr(lvl_step));
        }).add;

        // =====================================================================
        // SYNTH 5: ARP 1005
        // =====================================================================
        SynthDef(\Elianne_1005, {
            arg in_car, in_mod, in_vca, in_gate,
                out_main, out_inv, out_sum, out_diff,
                lvl_car, lvl_mod, lvl_vca, lvl_gate,
                lvl_main, lvl_inv, lvl_sum, lvl_diff,
                mod_gain=1, unmod_gain=1, drive=0.2, vca_base=0, vca_resp=0.5,
                xfade=0.05, state_mode=0, gate_thresh=0.5, phys_bus, shaper_buf;
                
            var sys_age, pink_cv, slew_time;
            var car, mod, vca_cv, gate_sig, c_bleed, m_bleed, age_rm;
            var hilb_c, hilb_m, sum_sig, diff_sig;
            var rm_raw, rm_sig, gate_trig, state_flip, current_state, state_smooth;
            var core_sig, vca_env, vca_final, final_sig;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            slew_time = 0.001 + (sys_age * 0.005);
            
            car = InFeedback.ar(in_car) * In.kr(lvl_car) + pink_cv;
            mod = InFeedback.ar(in_mod) * In.kr(lvl_mod) + pink_cv;
            
            vca_cv = Lag.ar(InFeedback.ar(in_vca) * In.kr(lvl_vca), slew_time);
            gate_sig = InFeedback.ar(in_gate) * In.kr(lvl_gate) + pink_cv;
            
            age_rm = K2A.ar(LFNoise2.kr(0.018)) * sys_age * 0.1;
            c_bleed = K2A.ar(In.kr(phys_bus + 2)) + age_rm;
            m_bleed = K2A.ar(In.kr(phys_bus + 3));
            
            rm_raw = DiodeRingMod.ar(car + c_bleed, mod + m_bleed);
            rm_sig = (rm_raw * 3.5).softclip; 
            
            hilb_c = Hilbert.ar(car);
            hilb_m = Hilbert.ar(mod);
            sum_sig = (hilb_c[0] * hilb_m[0]) - (hilb_c[1] * hilb_m[1]);
            diff_sig = (hilb_c[0] * hilb_m[0]) + (hilb_c[1] * hilb_m[1]);
            
            gate_trig = Schmidt.ar(gate_sig, gate_thresh, gate_thresh + 0.1);
            state_flip = ToggleFF.ar(gate_trig);
            
            current_state = Select.ar(K2A.ar(state_mode),[state_flip, DC.ar(1), DC.ar(0)]);
            state_smooth = Lag.ar(current_state, xfade);
            
            core_sig = XFade2.ar(car * unmod_gain * 1.2, rm_sig * mod_gain, state_smooth * 2 - 1);
            
            vca_env = (vca_base + (vca_cv * 5.0)).clip(0, 1);
            vca_final = LinXFade2.ar(vca_env, vca_env.squared, vca_resp * 2 - 1);
            
            final_sig = (core_sig * vca_final * 1.5).clip(-1.0, 1.0);
            
            Out.ar(out_main, Shaper.ar(shaper_buf, final_sig) * In.kr(lvl_main));
            Out.ar(out_inv, Shaper.ar(shaper_buf, rm_sig.clip(-1.0, 1.0)) * In.kr(lvl_inv)); 
            Out.ar(out_sum, Shaper.ar(shaper_buf, (sum_sig * 2.0).clip(-1.0, 1.0)) * In.kr(lvl_sum));
            Out.ar(out_diff, Shaper.ar(shaper_buf, (diff_sig * 2.0).clip(-1.0, 1.0)) * In.kr(lvl_diff));
        }).add;

        // =====================================================================
        // SYNTH 6 & 7: ARP 1047 (POLYNOMIAL RESONANCE BREAKUP)
        // =====================================================================
        SynthDef(\Elianne_1047, {
            arg in_aud, in_cv1, in_res, in_cv2,
                out_lp, out_bp, out_hp, out_notch,
                lvl_aud, lvl_cv1, lvl_res, lvl_cv2,
                lvl_lp, lvl_bp, lvl_hp, lvl_notch,
                cutoff=1000, fine=0, q=1, notch_ofs=0, final_q=2, out_lvl=1,
                cv2_mode=0, jfet=1.5, t_ping=0, phys_bus, seed_offset=0, shaper_buf;
                
            var sys_age, pink_cv, brown_cv, slew_time;
            var aud, cv1, res_cv, cv2, p_shift, age_fc, age_q;
            var man_ping, combined_trig, ping_env, exciter, cv2_mod;
            var f_mod, q_mod, svf_res;
            var filter_noise, drive_aud, lp, bp, hp;
            var notch_weight, notch;
            var post_drive, asym_clip;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            brown_cv = LeakDC.ar(BrownNoise.ar(0.0005 * (1.0 + (sys_age * 2.0))), 0.99);
            slew_time = 0.001 + (sys_age * 0.005);
            
            aud = InFeedback.ar(in_aud) * In.kr(lvl_aud);
            
            cv1 = Lag.ar(InFeedback.ar(in_cv1) * In.kr(lvl_cv1), slew_time);
            res_cv = Lag.ar(InFeedback.ar(in_res) * In.kr(lvl_res), slew_time);
            cv2 = Lag.ar(InFeedback.ar(in_cv2) * In.kr(lvl_cv2), slew_time); 
            p_shift = K2A.ar(In.kr(phys_bus + 4));
            
            cv1 = cv1 * (1.0 - (cv1.abs * 0.01 * (1.0 + sys_age)));
            cv2 = cv2 * (1.0 - (cv2.abs * 0.01 * (1.0 + sys_age)));
            
            age_fc = K2A.ar(LFNoise2.kr(0.0149 + seed_offset)) * sys_age * 0.05;
            age_q = K2A.ar(LFNoise2.kr(0.0197 + seed_offset)) * sys_age * 0.2;
            
            man_ping = K2A.ar(t_ping);
            combined_trig = (Schmidt.ar(cv2, 0.5, 0.6) * cv2_mode) + man_ping;
            ping_env = EnvGen.ar(Env.perc(0.001, final_q * 0.1), combined_trig);
            
            exciter = Decay.ar(K2A.ar(combined_trig), 0.01) * 5.0;
            
            cv2_mod = cv2 * (1 - cv2_mode);
            
            f_mod = (K2A.ar(cutoff) + fine) * (2.0 ** (cv1 * 5.0)) * (2.0 ** (cv2_mod * 5.0)) * (2.0 ** (ping_env * p_shift * 5.0)) * (1.0 + age_fc + brown_cv);
            f_mod = f_mod.clip(10, 20000);
            
            q_mod = (q + (res_cv * 100.0) + (ping_env * 500.0)) * (1.0 + age_q);
            q_mod = q_mod.clip(0.1, 500.0); 
            
            svf_res = q_mod.explin(0.1, 500.0, 0.0, 0.999);
            
            // Ruido rosa inyectado para excitar la auto-oscilación
            filter_noise = PinkNoise.ar(0.001) * (q_mod * 0.01);
            drive_aud = tanh((aud + filter_noise + exciter) * jfet);
            
            lp = SVF.ar(drive_aud, f_mod, svf_res, 1, 0, 0, 0, 0);
            bp = SVF.ar(drive_aud, f_mod, svf_res, 0, 1, 0, 0, 0);
            hp = SVF.ar(drive_aud, f_mod, svf_res, 0, 0, 1, 0, 0);
            
            notch_weight = 2.0 ** (notch_ofs * 2.0);
            notch = lp + (hp * notch_weight); 
            
            // Curva Polinómica de Ruptura (Solo actúa fuerte a Q > 400)
            post_drive = 1.0 + ((q_mod / 500.0).pow(8) * 6.0);
            
            // Función de Saturación Asimétrica
            asym_clip = { |sig, drive|
                var driven = sig * drive;
                Select.ar(driven > 0,[
                    (driven * 0.8).tanh / 0.8, // Picos negativos más suaves
                    driven.tanh                // Picos positivos duros
                ]);
            };
            
            lp = asym_clip.(lp, post_drive);
            bp = asym_clip.(bp, post_drive);
            hp = asym_clip.(hp, post_drive);
            notch = asym_clip.(notch, post_drive);
            
            Out.ar(out_lp, Shaper.ar(shaper_buf, lp.clip(-1.0, 1.0)) * out_lvl * In.kr(lvl_lp));
            Out.ar(out_bp, Shaper.ar(shaper_buf, bp.clip(-1.0, 1.0)) * out_lvl * In.kr(lvl_bp));
            Out.ar(out_hp, Shaper.ar(shaper_buf, hp.clip(-1.0, 1.0)) * out_lvl * In.kr(lvl_hp));
            Out.ar(out_notch, Shaper.ar(shaper_buf, notch.clip(-1.0, 1.0)) * out_lvl * In.kr(lvl_notch));
        }).add;

        // =====================================================================
        // SYNTH 8: NEXUS (MASTER SHAPER)
        // =====================================================================
        SynthDef(\Elianne_Nexus, {
            arg in_ml, in_mr, in_al, in_ar,
                out_ml, out_mr, out_tl, out_tr,
                lvl_ml, lvl_mr, lvl_al, lvl_ar,
                pan_ml, pan_mr, pan_al, pan_ar,
                lvl_oml, lvl_omr, lvl_otl, lvl_otr,
                cut_l=18000, cut_r=18000, res=0, tape_time=0.3, tape_fb=0.4, tape_mix=0.2,
                filt_byp=0, adc_mon=0, tape_mute=0, drive=1.0, master_vol=1.0, tape_erosion=0.0, 
                cv_dest_l=0, cv_dest_r=0, phys_bus, shaper_buf, master_shaper_buf;
                
            var sys_age, pink_cv, brown_cv;
            var cv_l, cv_r, vca_mod_l, vca_mod_r, pan_mod_l, pan_mod_r;
            var ml, mr, adc, al, ar, sum;
            var age_vcf_l, age_vcf_r;
            var filt_l, filt_r, filt_sig;
            var wow_amt, flut_amt, tape_in, wow, flutter, tape_time_lag, tape_dt, tape_raw, tape_sat_sig, tape_physics_cutoff, tape_out;
            var loop_dust_trig, loop_dropout_env, loop_gain_loss;
            var master, final_out;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            pink_cv = PinkNoise.ar(0.0001 * (1.0 + (sys_age * 2.0)));
            brown_cv = LeakDC.ar(BrownNoise.ar(0.0005 * (1.0 + (sys_age * 2.0))), 0.99);
            
            cv_l = InFeedback.ar(in_al) * In.kr(lvl_al) + pink_cv;
            cv_r = InFeedback.ar(in_ar) * In.kr(lvl_ar) + pink_cv;
            
            vca_mod_l = Select.ar(K2A.ar(cv_dest_l),[cv_l * 5.0, DC.ar(0.0)]);
            vca_mod_r = Select.ar(K2A.ar(cv_dest_r),[cv_r * 5.0, DC.ar(0.0)]);
            pan_mod_l = Select.ar(K2A.ar(cv_dest_l), [DC.ar(0.0), cv_l]);
            pan_mod_r = Select.ar(K2A.ar(cv_dest_r),[DC.ar(0.0), cv_r]);
            
            ml = Pan2.ar((InFeedback.ar(in_ml) * In.kr(lvl_ml) + pink_cv) * (1.0 + vca_mod_l).clip(0, 2), (In.kr(pan_ml) + pan_mod_l).clip(-1, 1));
            mr = Pan2.ar((InFeedback.ar(in_mr) * In.kr(lvl_mr) + pink_cv) * (1.0 + vca_mod_r).clip(0, 2), (In.kr(pan_mr) + pan_mod_r).clip(-1, 1));
            
            sum = (ml + mr) * drive;
            
            age_vcf_l = K2A.ar(LFNoise2.kr(0.0151)) * sys_age * 0.05;
            age_vcf_r = K2A.ar(LFNoise2.kr(0.0163)) * sys_age * 0.05;
            
            filt_l = DFM1.ar(sum[0], (cut_l * (1.0 + age_vcf_l + brown_cv)).clip(20, 18000), res, 1.0, 0.0, 0.0005);
            filt_r = DFM1.ar(sum[1], (cut_r * (1.0 + age_vcf_r + brown_cv)).clip(20, 18000), res, 1.0, 0.0, 0.0005);
            filt_sig = Select.ar(K2A.ar(filt_byp), [[filt_l, filt_r], sum]);
            
            wow_amt = In.kr(phys_bus + 5);
            flut_amt = In.kr(phys_bus + 6);
            tape_in = filt_sig + (LocalIn.ar(2) * tape_fb);
            
            tape_time_lag = Lag3.kr(tape_time, 0.5);
            wow = OnePole.kr(LFNoise2.kr(Rand(0.5, 2.0)) * wow_amt * 0.05, 0.95);
            flutter = LFNoise1.kr(15) * flut_amt * 0.005;
            
            tape_dt = (tape_time_lag + wow + flutter).clip(0.01, 6.1);
            tape_raw = DelayC.ar(tape_in, 6.2, tape_dt);
            tape_sat_sig = (tape_raw + (Delay1.ar(tape_raw) * 0.2)).tanh;
            
            tape_physics_cutoff = LinExp.kr(tape_time_lag.max(0.01), 0.01, 6.0, 15000, 1500);
            tape_out = LPF.ar(tape_sat_sig, tape_physics_cutoff);
            
            loop_dust_trig = Dust.kr(tape_erosion * 15);
            loop_dropout_env = Decay.kr(loop_dust_trig, 0.1);
            loop_gain_loss = (loop_dropout_env * tape_erosion).clip(0, 0.9);
            tape_out = tape_out * (1.0 - loop_gain_loss);
            
            LocalOut.ar(tape_out); 
            
            master = filt_sig + (tape_out * tape_mix * (1.0 - tape_mute));
            
            // MASTER SHAPER (Curva de Mastering) + Limiter
            final_out = Limiter.ar(Shaper.ar(master_shaper_buf, (master * master_vol).clip(-1.0, 1.0)), -0.11.dbamp);
            
            Out.ar(out_ml, final_out[0] * In.kr(lvl_oml));
            Out.ar(out_mr, final_out[1] * In.kr(lvl_omr));
            Out.ar(out_tl, Shaper.ar(shaper_buf, tape_out[0].clip(-1.0, 1.0)) * In.kr(lvl_otl));
            Out.ar(out_tr, Shaper.ar(shaper_buf, tape_out[1].clip(-1.0, 1.0)) * In.kr(lvl_otr));
        }).add;

        context.server.sync;

        // =====================================================================
        // INSTANCIACIÓN DE NODOS
        // =====================================================================
        
        synth_matrix_amps = Synth.new(\Elianne_MatrixAmps,[], context.xg, \addToHead);
        64.do { |i|
            synth_matrix_rows[i] = Synth.new(\Elianne_MatrixRow,[\out_bus, bus_nodes_rx.index + i], context.xg, \addToHead);
        };
        
        synth_adc = Synth.new(\Elianne_ADC,[
            \out_l, bus_nodes_tx.index+62, \out_r, bus_nodes_tx.index+63,
            \lvl_l, bus_levels.index+62, \lvl_r, bus_levels.index+63,
            \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToHead);
        
        synth_mods[0] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+0, \in_fm2, bus_nodes_rx.index+1, \in_pwm, bus_nodes_rx.index+2, \in_voct, bus_nodes_rx.index+3,
            \out_main, bus_nodes_tx.index+4, \out_inv, bus_nodes_tx.index+5, \out_sine, bus_nodes_tx.index+6, \out_pulse, bus_nodes_tx.index+7,
            \lvl_fm1, bus_levels.index+0, \lvl_fm2, bus_levels.index+1, \lvl_pwm, bus_levels.index+2, \lvl_voct, bus_levels.index+3,
            \lvl_main, bus_levels.index+4, \lvl_inv, bus_levels.index+5, \lvl_sine, bus_levels.index+6, \lvl_pulse, bus_levels.index+7,
            \fm1_type, 0, \fm2_type, 1, \phys_bus, bus_physics.index, \seed_offset, 0.1, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[1] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+8, \in_fm2, bus_nodes_rx.index+9, \in_pwm, bus_nodes_rx.index+10, \in_voct, bus_nodes_rx.index+11,
            \out_main, bus_nodes_tx.index+12, \out_inv, bus_nodes_tx.index+13, \out_sine, bus_nodes_tx.index+14, \out_pulse, bus_nodes_tx.index+15,
            \lvl_fm1, bus_levels.index+8, \lvl_fm2, bus_levels.index+9, \lvl_pwm, bus_levels.index+10, \lvl_voct, bus_levels.index+11,
            \lvl_main, bus_levels.index+12, \lvl_inv, bus_levels.index+13, \lvl_sine, bus_levels.index+14, \lvl_pulse, bus_levels.index+15,
            \fm1_type, 0, \fm2_type, 1, \phys_bus, bus_physics.index, \seed_offset, 0.2, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[2] = Synth.new(\Elianne_1023,[
            \in_fm1, bus_nodes_rx.index+16, \in_fm2, bus_nodes_rx.index+17, \in_pv1, bus_nodes_rx.index+18, \in_pv2, bus_nodes_rx.index+19,
            \out_o1, bus_nodes_tx.index+20, \out_o2, bus_nodes_tx.index+21, \out_i1, bus_nodes_tx.index+22, \out_i2, bus_nodes_tx.index+23,
            \lvl_fm1, bus_levels.index+16, \lvl_fm2, bus_levels.index+17, \lvl_pv1, bus_levels.index+18, \lvl_pv2, bus_levels.index+19,
            \lvl_o1, bus_levels.index+20, \lvl_o2, bus_levels.index+21, \lvl_i1, bus_levels.index+22, \lvl_i2, bus_levels.index+23,
            \out3_wave, 0, \out4_wave, 0, \phys_bus, bus_physics.index, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[3] = Synth.new(\Elianne_1016,[
            \in_sig, bus_nodes_rx.index+24, \in_clk, bus_nodes_rx.index+25,
            \out_n1, bus_nodes_tx.index+26, \out_n2, bus_nodes_tx.index+27, \out_slow, bus_nodes_tx.index+28, \out_step, bus_nodes_tx.index+29,
            \lvl_sig, bus_levels.index+24, \lvl_clk, bus_levels.index+25,
            \lvl_n1, bus_levels.index+26, \lvl_n2, bus_levels.index+27, \lvl_slow, bus_levels.index+28, \lvl_step, bus_levels.index+29,
            \phys_bus, bus_physics.index, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[4] = Synth.new(\Elianne_1005,[
            \in_car, bus_nodes_rx.index+30, \in_mod, bus_nodes_rx.index+31, \in_vca, bus_nodes_rx.index+32, \in_gate, bus_nodes_rx.index+33,
            \out_main, bus_nodes_tx.index+34, \out_inv, bus_nodes_tx.index+35, \out_sum, bus_nodes_tx.index+36, \out_diff, bus_nodes_tx.index+37,
            \lvl_car, bus_levels.index+30, \lvl_mod, bus_levels.index+31, \lvl_vca, bus_levels.index+32, \lvl_gate, bus_levels.index+33,
            \lvl_main, bus_levels.index+34, \lvl_inv, bus_levels.index+35, \lvl_sum, bus_levels.index+36, \lvl_diff, bus_levels.index+37,
            \phys_bus, bus_physics.index, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[5] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+38, \in_cv1, bus_nodes_rx.index+39, \in_res, bus_nodes_rx.index+40, \in_cv2, bus_nodes_rx.index+41,
            \out_lp, bus_nodes_tx.index+42, \out_bp, bus_nodes_tx.index+43, \out_hp, bus_nodes_tx.index+44, \out_notch, bus_nodes_tx.index+45,
            \lvl_aud, bus_levels.index+38, \lvl_cv1, bus_levels.index+39, \lvl_res, bus_levels.index+40, \lvl_cv2, bus_levels.index+41,
            \lvl_lp, bus_levels.index+42, \lvl_bp, bus_levels.index+43, \lvl_hp, bus_levels.index+44, \lvl_notch, bus_levels.index+45,
            \phys_bus, bus_physics.index, \seed_offset, 0.3, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[6] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+46, \in_cv1, bus_nodes_rx.index+47, \in_res, bus_nodes_rx.index+48, \in_cv2, bus_nodes_rx.index+49,
            \out_lp, bus_nodes_tx.index+50, \out_bp, bus_nodes_tx.index+51, \out_hp, bus_nodes_tx.index+52, \out_notch, bus_nodes_tx.index+53,
            \lvl_aud, bus_levels.index+46, \lvl_cv1, bus_levels.index+47, \lvl_res, bus_levels.index+48, \lvl_cv2, bus_levels.index+49,
            \lvl_lp, bus_levels.index+50, \lvl_bp, bus_levels.index+51, \lvl_hp, bus_levels.index+52, \lvl_notch, bus_levels.index+53,
            \phys_bus, bus_physics.index, \seed_offset, 0.4, \shaper_buf, ca3080_node_buf.bufnum
        ], context.xg, \addToTail);

        synth_mods[7] = Synth.new(\Elianne_Nexus,[
            \in_ml, bus_nodes_rx.index+54, \in_mr, bus_nodes_rx.index+55, \in_al, bus_nodes_rx.index+56, \in_ar, bus_nodes_rx.index+57,
            \out_ml, context.out_b.index, \out_mr, context.out_b.index+1, \out_tl, bus_nodes_tx.index+60, \out_tr, bus_nodes_tx.index+61,
            \lvl_ml, bus_levels.index+54, \lvl_mr, bus_levels.index+55, \lvl_al, bus_levels.index+56, \lvl_ar, bus_levels.index+57,
            \pan_ml, bus_pans.index+54, \pan_mr, bus_pans.index+55, \pan_al, bus_pans.index+56, \pan_ar, bus_pans.index+57,
            \lvl_oml, bus_levels.index+58, \lvl_omr, bus_levels.index+59, \lvl_otl, bus_levels.index+60, \lvl_otr, bus_levels.index+61,
            \phys_bus, bus_physics.index, \shaper_buf, ca3080_node_buf.bufnum, \master_shaper_buf, ca3080_master_buf.bufnum
        ], context.xg, \addToTail);

        // =====================================================================
        // COMANDOS OSC (LUA -> SC)
        // =====================================================================
        
        this.addCommand("patch_set", "iif", { |msg| 
            var dst = msg[1] - 1; 
            var src = msg[2] - 1;
            var val = msg[3];
            
            matrix_state[dst][src] = val;
            synth_matrix_rows[dst].set(\gains, matrix_state[dst]);
        });

        this.addCommand("patch_row_set", "is", { |msg|
            var dst, str, vals;
            dst = msg[1] - 1;
            str = msg[2].asString;
            vals = str.split($,).collect({ |item| item.asFloat });
            matrix_state[dst] = vals;
            synth_matrix_rows[dst].set(\gains, matrix_state[dst]);
        });
        
        this.addCommand("pause_matrix_row", "i", { |msg| synth_matrix_rows[msg[1]].run(false) });
        this.addCommand("resume_matrix_row", "i", { |msg| synth_matrix_rows[msg[1]].run(true) });

        this.addCommand("set_in_level", "if", { |msg| bus_levels.setAt(msg[1] - 1, msg[2]) });
        this.addCommand("set_out_level", "if", { |msg| bus_levels.setAt(msg[1] - 1, msg[2]) });
        this.addCommand("set_in_pan", "if", { |msg| bus_pans.setAt(msg[1] - 1, msg[2]) });
        
        this.addCommand("set_global_physics", "sf", { |msg|
            var idx = switch(msg[1].asString, "thermal", 0, "droop", 1, "c_bleed", 2, "m_bleed", 3, "p_shift", 4);
            bus_physics.setAt(idx, msg[2]);
        });
        this.addCommand("set_tape_physics", "sf", { |msg|
            var idx = switch(msg[1].asString, "wow", 5, "flutter", 6);
            bus_physics.setAt(idx, msg[2]);
        });

        // M1
        this.addCommand("m1_tune", "f", { |msg| synth_mods[0].set(\tune, msg[1]) });
        this.addCommand("m1_fine", "f", { |msg| synth_mods[0].set(\fine, msg[1]) });
        this.addCommand("m1_pwm", "f", { |msg| synth_mods[0].set(\pwm_base, msg[1]) });
        this.addCommand("m1_mix_sine", "f", { |msg| synth_mods[0].set(\mix_sine, msg[1]) });
        this.addCommand("m1_mix_tri", "f", { |msg| synth_mods[0].set(\mix_tri, msg[1]) });
        this.addCommand("m1_mix_saw", "f", { |msg| synth_mods[0].set(\mix_saw, msg[1]) });
        this.addCommand("m1_mix_pulse", "f", { |msg| synth_mods[0].set(\mix_pulse, msg[1]) });
        this.addCommand("m1_range", "i", { |msg| synth_mods[0].set(\range, msg[1]) });
        this.addCommand("m1_fm1_type", "i", { |msg| synth_mods[0].set(\fm1_type, msg[1]) });
        this.addCommand("m1_fm2_type", "i", { |msg| synth_mods[0].set(\fm2_type, msg[1]) });

        // M2
        this.addCommand("m2_tune", "f", { |msg| synth_mods[1].set(\tune, msg[1]) });
        this.addCommand("m2_fine", "f", { |msg| synth_mods[1].set(\fine, msg[1]) });
        this.addCommand("m2_pwm", "f", { |msg| synth_mods[1].set(\pwm_base, msg[1]) });
        this.addCommand("m2_mix_sine", "f", { |msg| synth_mods[1].set(\mix_sine, msg[1]) });
        this.addCommand("m2_mix_tri", "f", { |msg| synth_mods[1].set(\mix_tri, msg[1]) });
        this.addCommand("m2_mix_saw", "f", { |msg| synth_mods[1].set(\mix_saw, msg[1]) });
        this.addCommand("m2_mix_pulse", "f", { |msg| synth_mods[1].set(\mix_pulse, msg[1]) });
        this.addCommand("m2_range", "i", { |msg| synth_mods[1].set(\range, msg[1]) });
        this.addCommand("m2_fm1_type", "i", { |msg| synth_mods[1].set(\fm1_type, msg[1]) });
        this.addCommand("m2_fm2_type", "i", { |msg| synth_mods[1].set(\fm2_type, msg[1]) });

        // M3
        this.addCommand("m3_tune1", "f", { |msg| synth_mods[2].set(\tune1, msg[1]) });
        this.addCommand("m3_pwm1", "f", { |msg| synth_mods[2].set(\pwm1, msg[1]) });
        this.addCommand("m3_morph1", "f", { |msg| synth_mods[2].set(\morph1, msg[1]) });
        this.addCommand("m3_range1", "i", { |msg| synth_mods[2].set(\range1, msg[1]) });
        this.addCommand("m3_pv1_mode", "i", { |msg| synth_mods[2].set(\pv1_mode, msg[1]) });
        this.addCommand("m3_fm1_mode", "i", { |msg| synth_mods[2].set(\fm1_mode, msg[1]) });
        this.addCommand("m3_tune2", "f", { |msg| synth_mods[2].set(\tune2, msg[1]) });
        this.addCommand("m3_pwm2", "f", { |msg| synth_mods[2].set(\pwm2, msg[1]) });
        this.addCommand("m3_morph2", "f", { |msg| synth_mods[2].set(\morph2, msg[1]) });
        this.addCommand("m3_range2", "i", { |msg| synth_mods[2].set(\range2, msg[1]) });
        this.addCommand("m3_pv2_mode", "i", { |msg| synth_mods[2].set(\pv2_mode, msg[1]) });
        this.addCommand("m3_fm2_mode", "i", { |msg| synth_mods[2].set(\fm2_mode, msg[1]) });
        this.addCommand("m3_out3_wave", "i", { |msg| synth_mods[2].set(\out3_wave, msg[1]) });
        this.addCommand("m3_out4_wave", "i", { |msg| synth_mods[2].set(\out4_wave, msg[1]) });

        // M4
        this.addCommand("m4_slow_rate", "f", { |msg| synth_mods[3].set(\slow_rate, msg[1]) });
        this.addCommand("m4_tilt1", "f", { |msg| synth_mods[3].set(\tilt1, msg[1]) });
        this.addCommand("m4_tilt2", "f", { |msg| synth_mods[3].set(\tilt2, msg[1]) });
        this.addCommand("m4_type1", "i", { |msg| synth_mods[3].set(\type1, msg[1]) });
        this.addCommand("m4_type2", "i", { |msg| synth_mods[3].set(\type2, msg[1]) });
        this.addCommand("m4_clk_rate", "f", { |msg| synth_mods[3].set(\clk_rate, msg[1]) });
        this.addCommand("m4_prob_skew", "f", { |msg| synth_mods[3].set(\prob_skew, msg[1]) });
        this.addCommand("m4_glide", "f", { |msg| synth_mods[3].set(\glide, msg[1]) });
        this.addCommand("m4_clk_thresh", "f", { |msg| synth_mods[3].set(\clk_thresh, msg[1]) });

        // M5
        this.addCommand("m5_mod_gain", "f", { |msg| synth_mods[4].set(\mod_gain, msg[1]) });
        this.addCommand("m5_unmod_gain", "f", { |msg| synth_mods[4].set(\unmod_gain, msg[1]) });
        this.addCommand("m5_drive", "f", { |msg| synth_mods[4].set(\drive, msg[1]) });
        this.addCommand("m5_vca_base", "f", { |msg| synth_mods[4].set(\vca_base, msg[1]) });
        this.addCommand("m5_vca_resp", "f", { |msg| synth_mods[4].set(\vca_resp, msg[1]) });
        this.addCommand("m5_xfade", "f", { |msg| synth_mods[4].set(\xfade, msg[1]) });
        this.addCommand("m5_state_mode", "i", { |msg| synth_mods[4].set(\state_mode, msg[1]) });
        this.addCommand("m5_gate_thresh", "f", { |msg| synth_mods[4].set(\gate_thresh, msg[1]) });

        // M6
        this.addCommand("m6_cutoff", "f", { |msg| synth_mods[5].set(\cutoff, msg[1]) });
        this.addCommand("m6_fine", "f", { |msg| synth_mods[5].set(\fine, msg[1]) });
        this.addCommand("m6_q", "f", { |msg| synth_mods[5].set(\q, msg[1]) });
        this.addCommand("m6_notch", "f", { |msg| synth_mods[5].set(\notch_ofs, msg[1]) });
        this.addCommand("m6_final_q", "f", { |msg| synth_mods[5].set(\final_q, msg[1]) });
        this.addCommand("m6_out_lvl", "f", { |msg| synth_mods[5].set(\out_lvl, msg[1]) });
        this.addCommand("m6_jfet", "f", { |msg| synth_mods[5].set(\jfet, msg[1]) });
        this.addCommand("m6_cv2_mode", "i", { |msg| synth_mods[5].set(\cv2_mode, msg[1]) });
        this.addCommand("m6_ping", "", { synth_mods[5].set(\t_ping, 1) });

        // M7
        this.addCommand("m7_cutoff", "f", { |msg| synth_mods[6].set(\cutoff, msg[1]) });
        this.addCommand("m7_fine", "f", { |msg| synth_mods[6].set(\fine, msg[1]) });
        this.addCommand("m7_q", "f", { |msg| synth_mods[6].set(\q, msg[1]) });
        this.addCommand("m7_notch", "f", { |msg| synth_mods[6].set(\notch_ofs, msg[1]) });
        this.addCommand("m7_final_q", "f", { |msg| synth_mods[6].set(\final_q, msg[1]) });
        this.addCommand("m7_out_lvl", "f", { |msg| synth_mods[6].set(\out_lvl, msg[1]) });
        this.addCommand("m7_jfet", "f", { |msg| synth_mods[6].set(\jfet, msg[1]) });
        this.addCommand("m7_cv2_mode", "i", { |msg| synth_mods[6].set(\cv2_mode, msg[1]) });
        this.addCommand("m7_ping", "", { synth_mods[6].set(\t_ping, 1) });

        // M8
        this.addCommand("m8_cut_l", "f", { |msg| synth_mods[7].set(\cut_l, msg[1]) });
        this.addCommand("m8_cut_r", "f", { |msg| synth_mods[7].set(\cut_r, msg[1]) });
        this.addCommand("m8_res", "f", { |msg| synth_mods[7].set(\res, msg[1]) });
        this.addCommand("m8_tape_time", "f", { |msg| synth_mods[7].set(\tape_time, msg[1]) });
        this.addCommand("m8_tape_fb", "f", { |msg| synth_mods[7].set(\tape_fb, msg[1]) });
        this.addCommand("m8_tape_mix", "f", { |msg| synth_mods[7].set(\tape_mix, msg[1]) });
        this.addCommand("m8_drive", "f", { |msg| synth_mods[7].set(\drive, msg[1]) });
        this.addCommand("m8_filt_byp", "i", { |msg| synth_mods[7].set(\filt_byp, msg[1]) });
        this.addCommand("m8_adc_mon", "f", { |msg| synth_mods[7].set(\adc_mon, msg[1]) });
        this.addCommand("m8_tape_mute", "i", { |msg| synth_mods[7].set(\tape_mute, msg[1]) });
        this.addCommand("m8_master_vol", "f", { |msg| synth_mods[7].set(\master_vol, msg[1]) });
        this.addCommand("m8_erosion", "f", { |msg| synth_mods[7].set(\tape_erosion, msg[1]) });
        this.addCommand("m8_cv_dest_l", "i", { |msg| synth_mods[7].set(\cv_dest_l, msg[1]) });
        this.addCommand("m8_cv_dest_r", "i", { |msg| synth_mods[7].set(\cv_dest_r, msg[1]) });
    }

    free {
        synth_matrix_amps.free;
        synth_matrix_rows.do({ |s| if(s.notNil, { s.free }) });
        synth_mods.do({ |s| if(s.notNil, { s.free }) });
        synth_adc.free;
        ca3080_node_buf.free;
        ca3080_master_buf.free;
        bus_nodes_tx.free;
        bus_nodes_rx.free;
        bus_levels.free;
        bus_pans.free;
        bus_physics.free;
    }
}
