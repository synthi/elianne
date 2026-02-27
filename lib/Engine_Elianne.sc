// lib/Engine_Elianne.sc v0.3
// CHANGELOG v0.3:
// 1. ARCHITECTURE: Matriz Universal de 64x64 Nodos (Permite conexiones In->In, Out->Out).
// 2. DSP: Implementación completa de los 8 módulos con modelado físico extremo (Pi 4).
// 3. 1005 MODAMP: Transformada de Hilbert integrada para Single Sideband (Suma/Diferencia).
// 4. 1047 FILTER: Integración de SVF y circuito Keyboard Ping modelado.

Engine_Elianne : CroneEngine {
    // Buses de Arquitectura Universal
    var <bus_nodes_tx; // 64 buses: Lo que los nodos transmiten a la matriz
    var <bus_nodes_rx; // 64 buses: Lo que los nodos reciben de la matriz
    var <bus_levels;   // 64 buses (Control): Attenuverters de cada nodo
    var <bus_pans;     // 64 buses (Control): Paneo (Solo usado por Nexus)
    var <bus_physics;  // 10 buses (Control): Variables ambientales globales
    
    var <synth_matrix;
    var <synth_mods;
    
    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        // 1. ASIGNACIÓN DE BUSES
        bus_nodes_tx = Bus.audio(context.server, 64);
        bus_nodes_rx = Bus.audio(context.server, 64);
        bus_levels = Bus.control(context.server, 64);
        bus_pans = Bus.control(context.server, 64);
        bus_physics = Bus.control(context.server, 10);
        
        // Inicializar Attenuverters a 1.0 por defecto
        64.do { |i| bus_levels.setAt(i, 1.0) };
        
        synth_mods = Array.newClear(8);

        context.server.sync;

        // =====================================================================
        // SYNTH 0: MATRIZ UNIVERSAL 64x64 (Latencia Cero)
        // =====================================================================
        SynthDef(\Elianne_Matrix, {
            var tx = InFeedback.ar(bus_nodes_tx.index, 64);
            64.do { |dst_idx|
                var row_gains = NamedControl.kr(("row_" ++ (dst_idx + 1)).asSymbol, 0 ! 64);
                var sum = (tx * row_gains).sum;
                Out.ar(bus_nodes_rx.index + dst_idx, sum);
            };
        }).add;

        // =====================================================================
        // SYNTH 1 & 2: ARP 1004-T (Oscilador Complejo)
        // =====================================================================
        SynthDef(\Elianne_1004T, {
            arg in_fm1, in_fm2, in_pwm, in_voct,
                out_main, out_inv, out_sine, out_pulse,
                lvl_fm1, lvl_fm2, lvl_pwm, lvl_voct,
                lvl_main, lvl_inv, lvl_sine, lvl_pulse,
                tune=100.0, fine=0.0, pwm_base=0.5,
                mix_sine=1.0, mix_tri=0.0, mix_saw=0.0, mix_pulse=0.0,
                range=0, phys_bus;
                
            var fm1 = In.ar(in_fm1) * In.kr(lvl_fm1);
            var fm2 = In.ar(in_fm2) * In.kr(lvl_fm2);
            var pwm_mod = In.ar(in_pwm) * In.kr(lvl_pwm);
            var voct = In.ar(in_voct) * In.kr(lvl_voct);
            var thermal = LFNoise2.kr(0.01) * In.kr(phys_bus + 0); // Thermal Drift
            
            var base_freq = Select.kr(range, [tune, tune * 0.01]); // Audio o LFO
            var freq = (base_freq + fine + (fm1 * 50) + (fm2 * 50)) * (2.0 ** (voct + thermal));
            var pwm_final = (pwm_base + pwm_mod).clip(0.05, 0.95);
            
            var phase = Phasor.ar(0, freq * SampleDur.ir, 0, 1);
            var sig_tri = (phase * 2 - 1).abs * 2 - 1;
            var sig_saw = phase * 2 - 1;
            var sig_pulse = (phase > pwm_final) * 2 - 1;
            var sig_sine = sig_tri - (sig_tri.pow(3) / 6.0); // Conformador de diodos
            
            var mix = (sig_sine * mix_sine) + (sig_tri * mix_tri) + (sig_saw * mix_saw) + (sig_pulse * mix_pulse);
            
            Out.ar(out_main, mix * In.kr(lvl_main));
            Out.ar(out_inv, (mix * -1.0) * In.kr(lvl_inv));
            Out.ar(out_sine, sig_sine * In.kr(lvl_sine));
            Out.ar(out_pulse, sig_pulse * In.kr(lvl_pulse));
        }).add;

        // =====================================================================
        // SYNTH 3: ARP 1023 (Dual VCO con Radigue Morph)
        // =====================================================================
        SynthDef(\Elianne_1023, {
            arg in_fm1, in_fm2, in_pv1, in_pv2,
                out_o1, out_o2, out_i1, out_i2,
                lvl_fm1, lvl_fm2, lvl_pv1, lvl_pv2,
                lvl_o1, lvl_o2, lvl_i1, lvl_i2,
                tune1=100, pwm1=0.5, morph1=0, range1=0, pv1_mode=0,
                tune2=101, pwm2=0.5, morph2=0, range2=0, pv2_mode=0,
                phys_bus;
                
            var thermal = LFNoise2.kr(0.01) * In.kr(phys_bus + 0);
            
            // VCO 1
            var fm1 = In.ar(in_fm1) * In.kr(lvl_fm1);
            var pv1 = In.ar(in_pv1) * In.kr(lvl_pv1);
            var voct1 = pv1 * pv1_mode;
            var pwm_mod1 = pv1 * (1 - pv1_mode);
            var freq1 = (Select.kr(range1, [tune1, tune1*0.01]) + (fm1*50)) * (2.0 ** (voct1 + thermal));
            var ph1 = Phasor.ar(0, freq1 * SampleDur.ir, 0, 1);
            var tri1 = (ph1 * 2 - 1).abs * 2 - 1;
            var saw1 = ph1 * 2 - 1;
            var pul1 = (ph1 > (pwm1 + pwm_mod1).clip(0.05, 0.95)) * 2 - 1;
            var sin1 = tri1 - (tri1.pow(3) / 6.0);
            var sqr1 = (ph1 > 0.5) * 2 - 1;
            var waves1 =[sin1, tri1, saw1, sqr1, pul1, sin1.neg, tri1, saw1.neg, sqr1, pul1.neg];
            var mix1 = SelectX.ar(morph1 * 9.0, waves1);
            
            // VCO 2
            var fm2 = In.ar(in_fm2) * In.kr(lvl_fm2);
            var pv2 = In.ar(in_pv2) * In.kr(lvl_pv2);
            var voct2 = pv2 * pv2_mode;
            var pwm_mod2 = pv2 * (1 - pv2_mode);
            var freq2 = (Select.kr(range2, [tune2, tune2*0.01]) + (fm2*50)) * (2.0 ** (voct2 + thermal));
            var ph2 = Phasor.ar(0, freq2 * SampleDur.ir, 0, 1);
            var tri2 = (ph2 * 2 - 1).abs * 2 - 1;
            var saw2 = ph2 * 2 - 1;
            var pul2 = (ph2 > (pwm2 + pwm_mod2).clip(0.05, 0.95)) * 2 - 1;
            var sin2 = tri2 - (tri2.pow(3) / 6.0);
            var sqr2 = (ph2 > 0.5) * 2 - 1;
            var waves2 =[sin2, tri2, saw2, sqr2, pul2, sin2.neg, tri2, saw2.neg, sqr2, pul2.neg];
            var mix2 = SelectX.ar(morph2 * 9.0, waves2);
            
            Out.ar(out_o1, mix1 * In.kr(lvl_o1));
            Out.ar(out_o2, mix2 * In.kr(lvl_o2));
            Out.ar(out_i1, (mix1 * -1.0) * In.kr(lvl_i1));
            Out.ar(out_i2, (mix2 * -1.0) * In.kr(lvl_i2));
        }).add;

        // =====================================================================
        // SYNTH 4: ARP 1016/36 (Noise & Random S&H)
        // =====================================================================
        SynthDef(\Elianne_1016, {
            arg in_sig, in_clk, out_n1, out_n2, out_slow, out_step,
                lvl_sig, lvl_clk, lvl_n1, lvl_n2, lvl_slow, lvl_step,
                slow_rate=0.1, tilt1=0, tilt2=0, type1=0, type2=1,
                clk_rate=2.0, prob_skew=0, glide=0, phys_bus;
                
            var sig = In.ar(in_sig) * In.kr(lvl_sig);
            var clk_ext = In.ar(in_clk) * In.kr(lvl_clk);
            var droop_amt = In.kr(phys_bus + 1);
            
            // Generadores de Ruido
            var n_pink = PinkNoise.ar;
            var n_white = WhiteNoise.ar;
            var n_crackle = Crackle.ar(1.9);
            var n_rain = Dust2.ar(LFNoise1.kr(0.5).exprange(100, 1000));
            var n_lorenz = LFNoise0.ar(LFNoise1.kr(0.1).exprange(10, 100));
            var n_grit = Latch.ar(WhiteNoise.ar, Dust.ar(50));
            
            var noise1 = Select.ar(type1,[n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit]);
            var noise2 = Select.ar(type2,[n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit]);
            
            // Filtros Tilt
            noise1 = EQBand.ar(noise1, 1000, tilt1 * 12, 0.5);
            noise2 = EQBand.ar(noise2, 1000, tilt2 * 12, 0.5);
            
            // Reloj y S&H
            var clk_int = Impulse.ar(clk_rate);
            var clk_trig = clk_int + Schmidt.ar(clk_ext, 0.0, 0.1);
            var sh_src = Select.ar(sig > 0.001, [noise1, sig]); // Normalizado a Noise 1
            
            // Probability Skew (Buchla 266)
            var rand_val = Latch.ar(sh_src, clk_trig);
            var skewed = rand_val.sign * (rand_val.abs ** (2.0 ** prob_skew.neg));
            
            // Capacitor Droop
            var droop_env = EnvGen.ar(Env([1, 0], [10]), clk_trig);
            var step_out = Lag.ar(skewed * (1.0 - (droop_amt * (1.0 - droop_env))), glide);
            
            var slow_out = LFNoise2.ar(slow_rate);
            slow_out = slow_out.sign * (slow_out.abs ** (2.0 ** prob_skew.neg));
            
            Out.ar(out_n1, noise1 * In.kr(lvl_n1));
            Out.ar(out_n2, noise2 * In.kr(lvl_n2));
            Out.ar(out_slow, slow_out * In.kr(lvl_slow));
            Out.ar(out_step, step_out * In.kr(lvl_step));
        }).add;

        // =====================================================================
        // SYNTH 5: ARP 1005 (ModAmp / Bode Shifter)
        // =====================================================================
        SynthDef(\Elianne_1005, {
            arg in_car, in_mod, in_vca, in_gate,
                out_main, out_inv, out_sum, out_diff,
                lvl_car, lvl_mod, lvl_vca, lvl_gate,
                lvl_main, lvl_inv, lvl_sum, lvl_diff,
                mod_gain=1, unmod_gain=1, drive=0.2, vca_base=0, vca_resp=0.5,
                xfade=0.05, state_mode=0, phys_bus;
                
            var car = In.ar(in_car) * In.kr(lvl_car);
            var mod = In.ar(in_mod) * In.kr(lvl_mod);
            var vca_cv = In.ar(in_vca) * In.kr(lvl_vca);
            var gate_sig = In.ar(in_gate) * In.kr(lvl_gate);
            
            var c_bleed = In.kr(phys_bus + 2);
            var m_bleed = In.kr(phys_bus + 3);
            
            // Transformada de Hilbert para Single Sideband
            var hilb_c = Hilbert.ar(car);
            var hilb_m = Hilbert.ar(mod);
            var sum_sig = (hilb_c[0] * hilb_m[0]) - (hilb_c[1] * hilb_m[1]);
            var diff_sig = (hilb_c[0] * hilb_m[0]) + (hilb_c[1] * hilb_m[1]);
            
            // Ring Modulator Clásico con Bleed y Saturación
            var rm_sig = ((car + c_bleed) * (mod + m_bleed) * (1.0 + (drive * 5))).tanh;
            
            // Lógica de Estado (MOD / UNMOD)
            var gate_trig = Schmidt.ar(gate_sig, 0.5, 0.6);
            var state_flip = ToggleFF.ar(gate_trig);
            var current_state = Select.kr(state_mode,[state_flip, DC.kr(1), DC.kr(0)]); // 0:Auto, 1:ForceMOD, 2:ForceUNMOD
            var state_smooth = Lag.ar(K2A.ar(current_state), xfade);
            
            var core_sig = XFade2.ar(car * unmod_gain, rm_sig * mod_gain, state_smooth * 2 - 1);
            
            // VCA
            var vca_env = (vca_base + vca_cv).clip(0, 1);
            var vca_final = LinXFade2.ar(vca_env, vca_env.squared, vca_resp * 2 - 1);
            var final_sig = core_sig * vca_final;
            
            Out.ar(out_main, final_sig * In.kr(lvl_main));
            Out.ar(out_inv, (final_sig * -1.0) * In.kr(lvl_inv));
            Out.ar(out_sum, sum_sig * In.kr(lvl_sum));
            Out.ar(out_diff, diff_sig * In.kr(lvl_diff));
        }).add;

        // =====================================================================
        // SYNTH 6 & 7: ARP 1047 (Multimode Filter / Resonator)
        // =====================================================================
        SynthDef(\Elianne_1047, {
            arg in_aud, in_cv1, in_res, in_cv2,
                out_lp, out_bp, out_hp, out_notch,
                lvl_aud, lvl_cv1, lvl_res, lvl_cv2,
                lvl_lp, lvl_bp, lvl_hp, lvl_notch,
                cutoff=1000, fine=0, q=1, notch_ofs=0, final_q=2, out_lvl=1,
                cv2_mode=0, range=0, phys_bus;
                
            var aud = In.ar(in_aud) * In.kr(lvl_aud);
            var cv1 = In.ar(in_cv1) * In.kr(lvl_cv1);
            var res_cv = In.ar(in_res) * In.kr(lvl_res);
            var cv2 = In.ar(in_cv2) * In.kr(lvl_cv2);
            var p_shift = In.kr(phys_bus + 4);
            
            // Keyboard Ping Logic
            var ping_trig = Schmidt.ar(cv2, 0.5, 0.6) * cv2_mode;
            var ping_env = EnvGen.ar(Env.perc(0.001, final_q * 0.1), ping_trig);
            var cv2_mod = cv2 * (1 - cv2_mode);
            
            var base_f = Select.kr(range,[cutoff, cutoff * 0.01]);
            var f_mod = (base_f + fine + (cv1 * 1000) + (cv2_mod * 1000) + (ping_env * p_shift * 1000)).clip(10, 20000);
            var q_mod = (q + (res_cv * 10) + (ping_env * 500)).clip(0.1, 500);
            
            // SVF Core (sc3-plugins) con pre-saturación JFET
            var drive_aud = (aud * 1.5).tanh;
            var svf = SVF.ar(drive_aud, f_mod, q_mod, 1, 1, 1, 0, 0);
            var lp = svf[0];
            var bp = svf[1];
            var hp = svf[2];
            
            // Notch Asimétrico Analógico
            var notch_f = f_mod * (2.0 ** (notch_ofs * 3.0));
            var notch_svf = SVF.ar(drive_aud, notch_f, q_mod, 1, 0, 1, 0, 0);
            var notch = notch_svf[0] + (notch_svf[2] * 0.985); // Tolerancia de resistencia
            
            Out.ar(out_lp, lp * out_lvl * In.kr(lvl_lp));
            Out.ar(out_bp, bp * out_lvl * In.kr(lvl_bp));
            Out.ar(out_hp, hp * out_lvl * In.kr(lvl_hp));
            Out.ar(out_notch, notch * out_lvl * In.kr(lvl_notch));
        }).add;

        // =====================================================================
        // SYNTH 8: NEXUS (Mastering & Tape Echo)
        // =====================================================================
        SynthDef(\Elianne_Nexus, {
            arg in_ml, in_mr, in_al, in_ar,
                out_ml, out_mr, out_tl, out_tr,
                lvl_ml, lvl_mr, lvl_al, lvl_ar,
                pan_ml, pan_mr, pan_al, pan_ar,
                lvl_oml, lvl_omr, lvl_otl, lvl_otr,
                cut_l=20000, cut_r=20000, res=0, tape_time=0.3, tape_fb=0.4, tape_mix=0.2,
                filt_byp=0, adc_mon=0, tape_mute=0, phys_bus;
                
            var ml = Pan2.ar(In.ar(in_ml) * In.kr(lvl_ml), In.kr(pan_ml));
            var mr = Pan2.ar(In.ar(in_mr) * In.kr(lvl_mr), In.kr(pan_mr));
            var adc = SoundIn.ar([0, 1]);
            var al = Pan2.ar(adc[0] * In.kr(lvl_al), In.kr(pan_al));
            var ar = Pan2.ar(adc[1] * In.kr(lvl_ar), In.kr(pan_ar));
            
            var sum = ml + mr + al + ar;
            
            // Filtros 1006 (Moog Ladder 24dB)
            var filt_l = MoogFF.ar(sum[0], cut_l, res);
            var filt_r = MoogFF.ar(sum[1], cut_r, res);
            var filt_sig = Select.ar(filt_byp, [[filt_l, filt_r], sum]);
            
            // Tape Echo
            var wow_amt = In.kr(phys_bus + 5);
            var flut_amt = In.kr(phys_bus + 6);
            var tape_in = filt_sig + (LocalIn.ar(2) * tape_fb);
            var wow = LFNoise2.kr(0.5) * wow_amt * 0.05;
            var flutter = LFNoise1.kr(15) * flut_amt * 0.005;
            var tape_dt = (tape_time + wow + flutter).clip(0.01, 2.0);
            var tape_out = DelayC.ar(tape_in, 2.0, tape_dt);
            tape_out = (tape_out * 1.2).tanh; // Saturación de cinta
            LocalOut.ar(tape_out);
            
            // Mezcla Final
            var master = (filt_sig * (1.0 - tape_mix)) + (tape_out * tape_mix);
            master = master * (1.0 - tape_mute);
            var final_out = master + (adc * adc_mon);
            
            Out.ar(out_ml, final_out[0] * In.kr(lvl_oml));
            Out.ar(out_mr, final_out[1] * In.kr(lvl_omr));
            Out.ar(out_tl, tape_out[0] * In.kr(lvl_otl));
            Out.ar(out_tr, tape_out[1] * In.kr(lvl_otr));
        }).add;

        context.server.sync;

        // =====================================================================
        // INSTANCIACIÓN DE NODOS (Mapeo exacto a globals.lua)
        // =====================================================================
        
        synth_matrix = Synth.new(\Elianne_Matrix,[], context.xg, \addToHead);
        
        // Módulo 1: 1004-T (A)[Ins: 1-4, Outs: 5-8]
        synth_mods[0] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+0, \in_fm2, bus_nodes_rx.index+1, \in_pwm, bus_nodes_rx.index+2, \in_voct, bus_nodes_rx.index+3,
            \out_main, bus_nodes_tx.index+4, \out_inv, bus_nodes_tx.index+5, \out_sine, bus_nodes_tx.index+6, \out_pulse, bus_nodes_tx.index+7,
            \lvl_fm1, bus_levels.index+0, \lvl_fm2, bus_levels.index+1, \lvl_pwm, bus_levels.index+2, \lvl_voct, bus_levels.index+3,
            \lvl_main, bus_levels.index+4, \lvl_inv, bus_levels.index+5, \lvl_sine, bus_levels.index+6, \lvl_pulse, bus_levels.index+7,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 2: 1004-T (B)[Ins: 9-12, Outs: 13-16]
        synth_mods[1] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+8, \in_fm2, bus_nodes_rx.index+9, \in_pwm, bus_nodes_rx.index+10, \in_voct, bus_nodes_rx.index+11,
            \out_main, bus_nodes_tx.index+12, \out_inv, bus_nodes_tx.index+13, \out_sine, bus_nodes_tx.index+14, \out_pulse, bus_nodes_tx.index+15,
            \lvl_fm1, bus_levels.index+8, \lvl_fm2, bus_levels.index+9, \lvl_pwm, bus_levels.index+10, \lvl_voct, bus_levels.index+11,
            \lvl_main, bus_levels.index+12, \lvl_inv, bus_levels.index+13, \lvl_sine, bus_levels.index+14, \lvl_pulse, bus_levels.index+15,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 3: 1023 [Ins: 17-20, Outs: 21-24]
        synth_mods[2] = Synth.new(\Elianne_1023,[
            \in_fm1, bus_nodes_rx.index+16, \in_fm2, bus_nodes_rx.index+17, \in_pv1, bus_nodes_rx.index+18, \in_pv2, bus_nodes_rx.index+19,
            \out_o1, bus_nodes_tx.index+20, \out_o2, bus_nodes_tx.index+21, \out_i1, bus_nodes_tx.index+22, \out_i2, bus_nodes_tx.index+23,
            \lvl_fm1, bus_levels.index+16, \lvl_fm2, bus_levels.index+17, \lvl_pv1, bus_levels.index+18, \lvl_pv2, bus_levels.index+19,
            \lvl_o1, bus_levels.index+20, \lvl_o2, bus_levels.index+21, \lvl_i1, bus_levels.index+22, \lvl_i2, bus_levels.index+23,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 4: 1016[Ins: 25-26, Outs: 27-30]
        synth_mods[3] = Synth.new(\Elianne_1016,[
            \in_sig, bus_nodes_rx.index+24, \in_clk, bus_nodes_rx.index+25,
            \out_n1, bus_nodes_tx.index+26, \out_n2, bus_nodes_tx.index+27, \out_slow, bus_nodes_tx.index+28, \out_step, bus_nodes_tx.index+29,
            \lvl_sig, bus_levels.index+24, \lvl_clk, bus_levels.index+25,
            \lvl_n1, bus_levels.index+26, \lvl_n2, bus_levels.index+27, \lvl_slow, bus_levels.index+28, \lvl_step, bus_levels.index+29,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 5: 1005[Ins: 31-34, Outs: 35-38]
        synth_mods[4] = Synth.new(\Elianne_1005,[
            \in_car, bus_nodes_rx.index+30, \in_mod, bus_nodes_rx.index+31, \in_vca, bus_nodes_rx.index+32, \in_gate, bus_nodes_rx.index+33,
            \out_main, bus_nodes_tx.index+34, \out_inv, bus_nodes_tx.index+35, \out_sum, bus_nodes_tx.index+36, \out_diff, bus_nodes_tx.index+37,
            \lvl_car, bus_levels.index+30, \lvl_mod, bus_levels.index+31, \lvl_vca, bus_levels.index+32, \lvl_gate, bus_levels.index+33,
            \lvl_main, bus_levels.index+34, \lvl_inv, bus_levels.index+35, \lvl_sum, bus_levels.index+36, \lvl_diff, bus_levels.index+37,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 6: 1047 (A)[Ins: 39-42, Outs: 43-46]
        synth_mods[5] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+38, \in_cv1, bus_nodes_rx.index+39, \in_res, bus_nodes_rx.index+40, \in_cv2, bus_nodes_rx.index+41,
            \out_lp, bus_nodes_tx.index+42, \out_bp, bus_nodes_tx.index+43, \out_hp, bus_nodes_tx.index+44, \out_notch, bus_nodes_tx.index+45,
            \lvl_aud, bus_levels.index+38, \lvl_cv1, bus_levels.index+39, \lvl_res, bus_levels.index+40, \lvl_cv2, bus_levels.index+41,
            \lvl_lp, bus_levels.index+42, \lvl_bp, bus_levels.index+43, \lvl_hp, bus_levels.index+44, \lvl_notch, bus_levels.index+45,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 7: 1047 (B) [Ins: 47-50, Outs: 51-54]
        synth_mods[6] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+46, \in_cv1, bus_nodes_rx.index+47, \in_res, bus_nodes_rx.index+48, \in_cv2, bus_nodes_rx.index+49,
            \out_lp, bus_nodes_tx.index+50, \out_bp, bus_nodes_tx.index+51, \out_hp, bus_nodes_tx.index+52, \out_notch, bus_nodes_tx.index+53,
            \lvl_aud, bus_levels.index+46, \lvl_cv1, bus_levels.index+47, \lvl_res, bus_levels.index+48, \lvl_cv2, bus_levels.index+49,
            \lvl_lp, bus_levels.index+50, \lvl_bp, bus_levels.index+51, \lvl_hp, bus_levels.index+52, \lvl_notch, bus_levels.index+53,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // Módulo 8: NEXUS[Ins: 55-58, Outs: 59-62]
        synth_mods[7] = Synth.new(\Elianne_Nexus,[
            \in_ml, bus_nodes_rx.index+54, \in_mr, bus_nodes_rx.index+55, \in_al, bus_nodes_rx.index+56, \in_ar, bus_nodes_rx.index+57,
            \out_ml, context.out_b.index, \out_mr, context.out_b.index+1, \out_tl, bus_nodes_tx.index+60, \out_tr, bus_nodes_tx.index+61,
            \lvl_ml, bus_levels.index+54, \lvl_mr, bus_levels.index+55, \lvl_al, bus_levels.index+56, \lvl_ar, bus_levels.index+57,
            \pan_ml, bus_pans.index+54, \pan_mr, bus_pans.index+55, \pan_al, bus_pans.index+56, \pan_ar, bus_pans.index+57,
            \lvl_oml, bus_levels.index+58, \lvl_omr, bus_levels.index+59, \lvl_otl, bus_levels.index+60, \lvl_otr, bus_levels.index+61,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        // =====================================================================
        // COMANDOS OSC (LUA -> SC)
        // =====================================================================
        
        // Matriz y Nodos
        this.addCommand("patch_row", "iffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", { |msg| 
            synth_matrix.set(("row_" ++ msg[1]).asSymbol, msg.drop(2));
        });
        this.addCommand("set_in_level", "if", { |msg| bus_levels.setAt(msg[1] - 1, msg[2]) });
        this.addCommand("set_out_level", "if", { |msg| bus_levels.setAt(msg[1] - 1, msg[2]) });
        this.addCommand("set_in_pan", "if", { |msg| bus_pans.setAt(msg[1] - 1, msg[2]) });
        
        // Físicas Globales
        this.addCommand("set_global_physics", "sf", { |msg|
            var idx = switch(msg[1].asString, "thermal", 0, "droop", 1, "c_bleed", 2, "m_bleed", 3, "p_shift", 4);
            bus_physics.setAt(idx, msg[2]);
        });
        this.addCommand("set_tape_physics", "sf", { |msg|
            var idx = switch(msg[1].asString, "wow", 5, "flutter", 6);
            bus_physics.setAt(idx, msg[2]);
        });

        // Parámetros M1
        this.addCommand("m1_tune", "f", { |msg| synth_mods[0].set(\tune, msg[1]) });
        this.addCommand("m1_fine", "f", { |msg| synth_mods[0].set(\fine, msg[1]) });
        this.addCommand("m1_pwm", "f", { |msg| synth_mods[0].set(\pwm_base, msg[1]) });
        this.addCommand("m1_mix_sine", "f", { |msg| synth_mods[0].set(\mix_sine, msg[1]) });
        this.addCommand("m1_mix_tri", "f", { |msg| synth_mods[0].set(\mix_tri, msg[1]) });
        this.addCommand("m1_mix_saw", "f", { |msg| synth_mods[0].set(\mix_saw, msg[1]) });
        this.addCommand("m1_mix_pulse", "f", { |msg| synth_mods[0].set(\mix_pulse, msg[1]) });
        this.addCommand("m1_range", "i", { |msg| synth_mods[0].set(\range, msg[1] - 1) });

        // Parámetros M2
        this.addCommand("m2_tune", "f", { |msg| synth_mods[1].set(\tune, msg[1]) });
        this.addCommand("m2_fine", "f", { |msg| synth_mods[1].set(\fine, msg[1]) });
        this.addCommand("m2_pwm", "f", { |msg| synth_mods[1].set(\pwm_base, msg[1]) });
        this.addCommand("m2_mix_sine", "f", { |msg| synth_mods[1].set(\mix_sine, msg[1]) });
        this.addCommand("m2_mix_tri", "f", { |msg| synth_mods[1].set(\mix_tri, msg[1]) });
        this.addCommand("m2_mix_saw", "f", { |msg| synth_mods[1].set(\mix_saw, msg[1]) });
        this.addCommand("m2_mix_pulse", "f", { |msg| synth_mods[1].set(\mix_pulse, msg[1]) });
        this.addCommand("m2_range", "i", { |msg| synth_mods[1].set(\range, msg[1] - 1) });

        // Parámetros M3
        this.addCommand("m3_tune1", "f", { |msg| synth_mods[2].set(\tune1, msg[1]) });
        this.addCommand("m3_pwm1", "f", { |msg| synth_mods[2].set(\pwm1, msg[1]) });
        this.addCommand("m3_morph1", "f", { |msg| synth_mods[2].set(\morph1, msg[1]) });
        this.addCommand("m3_range1", "i", { |msg| synth_mods[2].set(\range1, msg[1] - 1) });
        this.addCommand("m3_tune2", "f", { |msg| synth_mods[2].set(\tune2, msg[1]) });
        this.addCommand("m3_pwm2", "f", { |msg| synth_mods[2].set(\pwm2, msg[1]) });
        this.addCommand("m3_morph2", "f", { |msg| synth_mods[2].set(\morph2, msg[1]) });
        this.addCommand("m3_range2", "i", { |msg| synth_mods[2].set(\range2, msg[1] - 1) });

        // Parámetros M4
        this.addCommand("m4_slow_rate", "f", { |msg| synth_mods[3].set(\slow_rate, msg[1]) });
        this.addCommand("m4_tilt1", "f", { |msg| synth_mods[3].set(\tilt1, msg[1]) });
        this.addCommand("m4_tilt2", "f", { |msg| synth_mods[3].set(\tilt2, msg[1]) });
        this.addCommand("m4_type1", "i", { |msg| synth_mods[3].set(\type1, msg[1] - 1) });
        this.addCommand("m4_type2", "i", { |msg| synth_mods[3].set(\type2, msg[1] - 1) });
        this.addCommand("m4_clk_rate", "f", { |msg| synth_mods[3].set(\clk_rate, msg[1]) });
        this.addCommand("m4_prob_skew", "f", { |msg| synth_mods[3].set(\prob_skew, msg[1]) });
        this.addCommand("m4_glide", "f", { |msg| synth_mods[3].set(\glide, msg[1]) });

        // Parámetros M5
        this.addCommand("m5_mod_gain", "f", { |msg| synth_mods[4].set(\mod_gain, msg[1]) });
        this.addCommand("m5_unmod_gain", "f", { |msg| synth_mods[4].set(\unmod_gain, msg[1]) });
        this.addCommand("m5_drive", "f", { |msg| synth_mods[4].set(\drive, msg[1]) });
        this.addCommand("m5_vca_base", "f", { |msg| synth_mods[4].set(\vca_base, msg[1]) });
        this.addCommand("m5_vca_resp", "f", { |msg| synth_mods[4].set(\vca_resp, msg[1]) });
        this.addCommand("m5_xfade", "f", { |msg| synth_mods[4].set(\xfade, msg[1]) });

        // Parámetros M6
        this.addCommand("m6_cutoff", "f", { |msg| synth_mods[5].set(\cutoff, msg[1]) });
        this.addCommand("m6_fine", "f", { |msg| synth_mods[5].set(\fine, msg[1]) });
        this.addCommand("m6_q", "f", { |msg| synth_mods[5].set(\q, msg[1]) });
        this.addCommand("m6_notch", "f", { |msg| synth_mods[5].set(\notch_ofs, msg[1]) });
        this.addCommand("m6_final_q", "f", { |msg| synth_mods[5].set(\final_q, msg[1]) });
        this.addCommand("m6_out_lvl", "f", { |msg| synth_mods[5].set(\out_lvl, msg[1]) });

        // Parámetros M7
        this.addCommand("m7_cutoff", "f", { |msg| synth_mods[6].set(\cutoff, msg[1]) });
        this.addCommand("m7_fine", "f", { |msg| synth_mods[6].set(\fine, msg[1]) });
        this.addCommand("m7_q", "f", { |msg| synth_mods[6].set(\q, msg[1]) });
        this.addCommand("m7_notch", "f", { |msg| synth_mods[6].set(\notch_ofs, msg[1]) });
        this.addCommand("m7_final_q", "f", { |msg| synth_mods[6].set(\final_q, msg[1]) });
        this.addCommand("m7_out_lvl", "f", { |msg| synth_mods[6].set(\out_lvl, msg[1]) });

        // Parámetros M8
        this.addCommand("m8_cut_l", "f", { |msg| synth_mods[7].set(\cut_l, msg[1]) });
        this.addCommand("m8_cut_r", "f", { |msg| synth_mods[7].set(\cut_r, msg[1]) });
        this.addCommand("m8_res", "f", { |msg| synth_mods[7].set(\res, msg[1]) });
        this.addCommand("m8_tape_time", "f", { |msg| synth_mods[7].set(\tape_time, msg[1]) });
        this.addCommand("m8_tape_fb", "f", { |msg| synth_mods[7].set(\tape_fb, msg[1]) });
        this.addCommand("m8_tape_mix", "f", { |msg| synth_mods[7].set(\tape_mix, msg[1]) });
    }

    free {
        synth_matrix.free;
        synth_mods.do({ |s| if(s.notNil, { s.free }) });
        bus_nodes_tx.free;
        bus_nodes_rx.free;
        bus_levels.free;
        bus_pans.free;
        bus_physics.free;
    }
}
