// lib/Engine_Elianne.sc v0.100
// CHANGELOG v0.100:
// 1. OPTIMIZATION: Dynamic Node Pausing (pause_matrix_row).
// 2. OPTIMIZATION: System Age movido a .kr con K2A.ar para ahorrar 10% CPU.
// 3. DSP: Falso Seno con inyección DC y LeakDC.
// 4. DSP: Crossover Distortion en 1005.
// 5. DSP: Histéresis magnética en Nexus Tape.
// 6. DSP: Ping 1047 inyectado directamente al núcleo de audio.

Engine_Elianne : CroneEngine {
    var <bus_nodes_tx;
    var <bus_nodes_rx;
    var <bus_levels;
    var <bus_pans;
    var <bus_physics;
    
    var <synth_matrix_amps;
    var <synth_matrix_rows;
    var <synth_mods;
    var matrix_state;
    
    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        bus_nodes_tx = Bus.audio(context.server, 64);
        bus_nodes_rx = Bus.audio(context.server, 64);
        bus_levels = Bus.control(context.server, 64);
        bus_pans = Bus.control(context.server, 64);
        bus_physics = Bus.control(context.server, 10);
        
        64.do { |i| bus_levels.setAt(i, 0.5) }; // Default 0.5
        
        synth_mods = Array.newClear(8);
        synth_matrix_rows = Array.newClear(64);
        matrix_state = Array.fill(64, { Array.fill(64, 0.0) });

        context.server.sync;

        OSCFunc({ |msg|
            NetAddr("127.0.0.1", 10111).sendMsg("/elianne_levels", *msg.drop(3));
        }, '/elianne_levels', context.server.addr).fix;

        // =====================================================================
        // SYNTH 0A & 0B: MATRIZ
        // =====================================================================
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

        // =====================================================================
        // SYNTH 1 & 2: ARP 1004-P
        // =====================================================================
        SynthDef(\Elianne_1004T, {
            arg in_fm1, in_fm2, in_pwm, in_voct,
                out_main, out_inv, out_sine, out_pulse,
                lvl_fm1, lvl_fm2, lvl_pwm, lvl_voct,
                lvl_main, lvl_inv, lvl_sine, lvl_pulse,
                tune=100.0, fine=0.0, pwm_base=0.5,
                mix_sine=1.0, mix_tri=0.0, mix_saw=0.0, mix_pulse=0.0,
                range=0, phys_bus, seed_offset=0;
                
            var fm1, fm2, pwm_mod, voct;
            var sys_age, age_pitch, age_shape, age_amp;
            var base_freq, freq, pwm_final, phase;
            var raw_tri, sqr, sig_tri, sig_saw, sig_pulse, sig_sine, mix;
            
            fm1 = InFeedback.ar(in_fm1) * In.kr(lvl_fm1);
            fm2 = InFeedback.ar(in_fm2) * In.kr(lvl_fm2);
            pwm_mod = InFeedback.ar(in_pwm) * In.kr(lvl_pwm);
            voct = InFeedback.ar(in_voct) * In.kr(lvl_voct);
            
            // SYSTEM AGE: Optimizado a .kr
            sys_age = In.kr(phys_bus + 0) * 10.0; 
            age_pitch = K2A.ar(LFNoise2.kr(0.0113 + seed_offset)) * sys_age * 0.02;
            age_shape = K2A.ar(LFNoise2.kr(0.0171 + seed_offset)) * sys_age * 0.05;
            age_amp = 1.0 - (K2A.ar(LFNoise2.kr(0.0233 + seed_offset)).range(0, 0.1) * sys_age);
            
            base_freq = Select.kr(range,[tune, tune * 0.01]);
            freq = (K2A.ar(base_freq + fine) + (fm1 * 50) + (fm2 * 50)) * (2.0 ** (voct + age_pitch));
            pwm_final = (pwm_base + pwm_mod).clip(0.05, 0.95);
            
            phase = Phasor.ar(0, freq * SampleDur.ir, 0, 1);
            raw_tri = (phase * 2 - 1).abs * 2 - 1 + age_shape; 
            sqr = (phase > 0.5) * 2 - 1;
            
            // FALSO SENO: Inyección DC y LeakDC
            sig_tri = LeakDC.ar(raw_tri + 0.015);
            sig_saw = (phase * 2 - 1) + (HPF.ar(Impulse.ar(freq), 10000) * 0.1);
            sig_pulse = (sig_tri > ((pwm_final * 2) - 1)) * 2 - 1;
            sig_sine = LeakDC.ar(sig_tri - (sig_tri.pow(3) / 6.0)) + (sqr * 0.02);
            
            mix = ((sig_sine * mix_sine) + (sig_tri * mix_tri) + (sig_saw * mix_saw) + (sig_pulse * mix_pulse)) * age_amp;
            
            Out.ar(out_main, mix * In.kr(lvl_main));
            Out.ar(out_inv, sig_tri * In.kr(lvl_inv)); 
            Out.ar(out_sine, sig_sine * In.kr(lvl_sine));
            Out.ar(out_pulse, sig_pulse * In.kr(lvl_pulse));
        }).add;

        // =====================================================================
        // SYNTH 3: ARP 1023
        // =====================================================================
        SynthDef(\Elianne_1023, {
            arg in_fm1, in_fm2, in_pv1, in_pv2,
                out_o1, out_o2, out_i1, out_i2,
                lvl_fm1, lvl_fm2, lvl_pv1, lvl_pv2,
                lvl_o1, lvl_o2, lvl_i1, lvl_i2,
                tune1=100, pwm1=0.5, morph1=0, range1=0, pv1_mode=0,
                tune2=101, pwm2=0.5, morph2=0, range2=0, pv2_mode=0,
                phys_bus;
                
            var sys_age, age_p1, age_s1, age_a1, age_p2, age_s2, age_a2;
            var fm1, pv1, voct1, pwm_mod1, freq1, ph1, rtri1, sqr1, tri1, saw1, pul1, sin1, waves1, mix1;
            var fm2, pv2, voct2, pwm_mod2, freq2, ph2, rtri2, sqr2, tri2, saw2, pul2, sin2, waves2, mix2;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            age_p1 = K2A.ar(LFNoise2.kr(0.0127)) * sys_age * 0.02;
            age_s1 = K2A.ar(LFNoise2.kr(0.0181)) * sys_age * 0.05;
            age_a1 = 1.0 - (K2A.ar(LFNoise2.kr(0.0241)).range(0, 0.1) * sys_age);
            age_p2 = K2A.ar(LFNoise2.kr(0.0139)) * sys_age * 0.02;
            age_s2 = K2A.ar(LFNoise2.kr(0.0193)) * sys_age * 0.05;
            age_a2 = 1.0 - (K2A.ar(LFNoise2.kr(0.0257)).range(0, 0.1) * sys_age);
            
            // VCO 1
            fm1 = InFeedback.ar(in_fm1) * In.kr(lvl_fm1);
            pv1 = InFeedback.ar(in_pv1) * In.kr(lvl_pv1);
            voct1 = pv1 * pv1_mode;
            pwm_mod1 = pv1 * (1 - pv1_mode);
            freq1 = (K2A.ar(Select.kr(range1, [tune1, tune1*0.01])) + (fm1*50)) * (2.0 ** (voct1 + age_p1));
            
            ph1 = Phasor.ar(0, freq1 * SampleDur.ir, 0, 1);
            rtri1 = (ph1 * 2 - 1).abs * 2 - 1 + age_s1;
            sqr1 = (ph1 > 0.5) * 2 - 1;
            tri1 = LeakDC.ar(rtri1 + 0.015);
            saw1 = (ph1 * 2 - 1) + (HPF.ar(Impulse.ar(freq1), 10000) * 0.1);
            pul1 = (tri1 > (((pwm1 + pwm_mod1).clip(0.05, 0.95) * 2) - 1)) * 2 - 1;
            sin1 = LeakDC.ar(tri1 - (tri1.pow(3) / 6.0)) + (sqr1 * 0.02);
            
            waves1 =[sin1, tri1, saw1, sqr1, pul1, sin1.neg, tri1, saw1.neg, sqr1, pul1.neg];
            mix1 = SelectX.ar(morph1 * 9.0, waves1) * age_a1;
            
            // VCO 2
            fm2 = InFeedback.ar(in_fm2) * In.kr(lvl_fm2);
            pv2 = InFeedback.ar(in_pv2) * In.kr(lvl_pv2);
            voct2 = pv2 * pv2_mode;
            pwm_mod2 = pv2 * (1 - pv2_mode);
            freq2 = (K2A.ar(Select.kr(range2,[tune2, tune2*0.01])) + (fm2*50)) * (2.0 ** (voct2 + age_p2));
            
            ph2 = Phasor.ar(0, freq2 * SampleDur.ir, 0, 1);
            rtri2 = (ph2 * 2 - 1).abs * 2 - 1 + age_s2;
            sqr2 = (ph2 > 0.5) * 2 - 1;
            tri2 = LeakDC.ar(rtri2 + 0.015);
            saw2 = (ph2 * 2 - 1) + (HPF.ar(Impulse.ar(freq2), 10000) * 0.1);
            pul2 = (tri2 > (((pwm2 + pwm_mod2).clip(0.05, 0.95) * 2) - 1)) * 2 - 1;
            sin2 = LeakDC.ar(tri2 - (tri2.pow(3) / 6.0)) + (sqr2 * 0.02);
            
            waves2 =[sin2, tri2, saw2, sqr2, pul2, sin2.neg, tri2, saw2.neg, sqr2, pul2.neg];
            mix2 = SelectX.ar(morph2 * 9.0, waves2) * age_a2;
            
            Out.ar(out_o1, mix1 * In.kr(lvl_o1));
            Out.ar(out_o2, mix2 * In.kr(lvl_o2));
            Out.ar(out_i1, sin1 * In.kr(lvl_i1)); 
            Out.ar(out_i2, sin2 * In.kr(lvl_i2)); 
        }).add;

        // =====================================================================
        // SYNTH 4: ARP 1016/36
        // =====================================================================
        SynthDef(\Elianne_1016, {
            arg in_sig, in_clk, out_n1, out_n2, out_slow, out_step,
                lvl_sig, lvl_clk, lvl_n1, lvl_n2, lvl_slow, lvl_step,
                slow_rate=0.1, tilt1=0, tilt2=0, type1=0, type2=1,
                clk_rate=2.0, prob_skew=0, glide=0, clk_thresh=0.1, phys_bus;
                
            var sig, clk_ext, droop_amt;
            var n_pink, n_white, n_crackle, n_rain, n_lorenz, n_grit;
            var noise1, noise2, clk_int, clk_trig;
            var sh_src, rand_val, skewed, droop_env, step_out, slow_out;
            
            sig = InFeedback.ar(in_sig) * In.kr(lvl_sig);
            clk_ext = InFeedback.ar(in_clk) * In.kr(lvl_clk);
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
            
            droop_env = EnvGen.ar(Env([1, 0], [10]), clk_trig);
            step_out = Lag.ar(skewed * (1.0 - (droop_amt * (1.0 - droop_env))), glide);
            
            slow_out = LFNoise2.ar(slow_rate);
            slow_out = slow_out.sign * (slow_out.abs ** (2.0 ** prob_skew.neg));
            
            Out.ar(out_n1, noise1 * In.kr(lvl_n1));
            Out.ar(out_n2, noise2 * In.kr(lvl_n2));
            Out.ar(out_slow, slow_out * In.kr(lvl_slow));
            Out.ar(out_step, step_out * In.kr(lvl_step));
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
                xfade=0.05, state_mode=0, gate_thresh=0.5, phys_bus;
                
            var car, mod, vca_cv, gate_sig, c_bleed, m_bleed, sys_age, age_rm;
            var hilb_c, hilb_m, sum_sig, diff_sig;
            var car_cross, mod_cross, rm_raw, rm_sig, gate_trig, state_flip, current_state, state_smooth;
            var core_sig, vca_env, vca_final, final_sig;
            
            car = InFeedback.ar(in_car) * In.kr(lvl_car);
            mod = InFeedback.ar(in_mod) * In.kr(lvl_mod);
            vca_cv = InFeedback.ar(in_vca) * In.kr(lvl_vca);
            gate_sig = InFeedback.ar(in_gate) * In.kr(lvl_gate);
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            age_rm = K2A.ar(LFNoise2.kr(0.018)) * sys_age * 0.1;
            
            c_bleed = K2A.ar(In.kr(phys_bus + 2)) + age_rm;
            m_bleed = K2A.ar(In.kr(phys_bus + 3));
            
            hilb_c = Hilbert.ar(car);
            hilb_m = Hilbert.ar(mod);
            sum_sig = (hilb_c[0] * hilb_m[0]) - (hilb_c[1] * hilb_m[1]);
            diff_sig = (hilb_c[0] * hilb_m[0]) + (hilb_c[1] * hilb_m[1]);
            
            // CROSSOVER DISTORTION
            car_cross = (car.abs - 0.02).max(0) * car.sign;
            mod_cross = (mod.abs - 0.02).max(0) * mod.sign;
            rm_raw = (car_cross + c_bleed) * (mod_cross + m_bleed) * (1.0 + (drive * 5));
            rm_sig = OnePole.ar(rm_raw.tanh, 0.4);
            
            gate_trig = Schmidt.ar(gate_sig, gate_thresh, gate_thresh + 0.1);
            state_flip = ToggleFF.ar(gate_trig);
            
            current_state = Select.ar(K2A.ar(state_mode),[state_flip, DC.ar(1), DC.ar(0)]);
            state_smooth = Lag.ar(current_state, xfade);
            
            core_sig = XFade2.ar(car * unmod_gain, rm_sig * mod_gain, state_smooth * 2 - 1);
            
            vca_env = (vca_base + vca_cv).clip(0, 1);
            vca_final = LinXFade2.ar(vca_env, vca_env.squared, vca_resp * 2 - 1);
            final_sig = core_sig * vca_final;
            
            Out.ar(out_main, final_sig * In.kr(lvl_main));
            Out.ar(out_inv, rm_sig * In.kr(lvl_inv)); 
            Out.ar(out_sum, sum_sig * In.kr(lvl_sum));
            Out.ar(out_diff, diff_sig * In.kr(lvl_diff));
        }).add;

        // =====================================================================
        // SYNTH 6 & 7: ARP 1047
        // =====================================================================
        SynthDef(\Elianne_1047, {
            arg in_aud, in_cv1, in_res, in_cv2,
                out_lp, out_bp, out_hp, out_notch,
                lvl_aud, lvl_cv1, lvl_res, lvl_cv2,
                lvl_lp, lvl_bp, lvl_hp, lvl_notch,
                cutoff=1000, fine=0, q=1, notch_ofs=0, final_q=2, out_lvl=1,
                cv2_mode=0, range=0, jfet=1.5, t_ping=0, phys_bus, seed_offset=0;
                
            var aud, cv1, res_cv, cv2, p_shift, sys_age, age_fc, age_q;
            var combined_trig, ping_env, exciter, cv2_mod;
            var base_f, f_mod, q_mod;
            var drive_raw, drive_aud, lp, bp, hp;
            var notch_f, notch_svf_lp, notch_svf_hp, notch;
            
            aud = InFeedback.ar(in_aud) * In.kr(lvl_aud);
            cv1 = InFeedback.ar(in_cv1) * In.kr(lvl_cv1);
            res_cv = InFeedback.ar(in_res) * In.kr(lvl_res);
            cv2 = InFeedback.ar(in_cv2) * In.kr(lvl_cv2);
            p_shift = K2A.ar(In.kr(phys_bus + 4));
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            age_fc = K2A.ar(LFNoise2.kr(0.0149 + seed_offset)) * sys_age * 0.05;
            age_q = K2A.ar(LFNoise2.kr(0.0197 + seed_offset)) * sys_age * 0.2;
            
            // LÓGICA DE PING (Serge VCFQ / ARP 1047 Style)
            // Sumamos el trigger del CV2 y el trigger manual (t_ping)
            combined_trig = (Schmidt.ar(cv2, 0.5, 0.6) * cv2_mode) + K2A.ar(t_ping);
            
            // 1. Envolvente de Resonancia (Ringing)
            ping_env = EnvGen.ar(Env.perc(0.001, final_q * 0.1), combined_trig);
            
            // 2. Excitador Acústico (Spike de 5ms a máximo volumen)
            exciter = EnvGen.ar(Env.perc(0.0001, 0.005), combined_trig) * 5.0;
            
            cv2_mod = cv2 * (1 - cv2_mode);
            
            base_f = K2A.ar(Select.kr(range, [cutoff, cutoff * 0.01]));
            f_mod = (base_f + fine + (cv1 * 1000) + (cv2_mod * 1000) + (ping_env * p_shift * 1000)) * (1.0 + age_fc);
            f_mod = f_mod.clip(10, 20000);
            
            q_mod = (q + (res_cv * 10) + (ping_env * 500)) * (1.0 + age_q);
            q_mod = q_mod.clip(0.1, 400); // Tope de seguridad para evitar explosión matemática
            
            // INYECCIÓN DIRECTA AL NÚCLEO DE AUDIO
            drive_raw = (aud * jfet) + exciter;
            drive_aud = OnePole.ar(drive_raw.tanh, 0.4);
            
            lp = SVF.ar(drive_aud, f_mod, q_mod, 1, 0, 0, 0, 0);
            bp = SVF.ar(drive_aud, f_mod, q_mod, 0, 1, 0, 0, 0);
            hp = SVF.ar(drive_aud, f_mod, q_mod, 0, 0, 1, 0, 0);
            
            notch_f = (f_mod * (2.0 ** (notch_ofs * 3.0))).clip(10, 20000);
            notch_svf_lp = SVF.ar(drive_aud, f_mod, q_mod, 1, 0, 0, 0, 0);
            notch_svf_hp = SVF.ar(drive_aud, notch_f, q_mod, 0, 0, 1, 0, 0);
            notch = notch_svf_lp + notch_svf_hp; 
            
            Out.ar(out_lp, lp * out_lvl * In.kr(lvl_lp));
            Out.ar(out_bp, bp * out_lvl * In.kr(lvl_bp));
            Out.ar(out_hp, hp * out_lvl * In.kr(lvl_hp));
            Out.ar(out_notch, notch * out_lvl * In.kr(lvl_notch));
        }).add;

        // =====================================================================
        // SYNTH 8: NEXUS
        // =====================================================================
        SynthDef(\Elianne_Nexus, {
            arg in_ml, in_mr, in_al, in_ar,
                out_ml, out_mr, out_tl, out_tr,
                lvl_ml, lvl_mr, lvl_al, lvl_ar,
                pan_ml, pan_mr, pan_al, pan_ar,
                lvl_oml, lvl_omr, lvl_otl, lvl_otr,
                cut_l=20000, cut_r=20000, res=0, tape_time=0.3, tape_fb=0.4, tape_mix=0.2,
                filt_byp=0, adc_mon=0, tape_mute=0, drive=1.0, master_vol=1.0, tape_erosion=0.0, phys_bus;
                
            var ml, mr, adc, al, ar, sum;
            var sys_age, age_vcf_l, age_vcf_r;
            var filt_l, filt_r, filt_sig;
            var wow_amt, flut_amt, tape_in, wow, flutter, tape_time_lag, tape_dt, tape_raw, tape_sat_sig, tape_physics_cutoff, tape_out;
            var loop_dust_trig, loop_dropout_env, loop_gain_loss;
            var master, final_out;
            
            ml = Pan2.ar(InFeedback.ar(in_ml) * In.kr(lvl_ml), In.kr(pan_ml));
            mr = Pan2.ar(InFeedback.ar(in_mr) * In.kr(lvl_mr), In.kr(pan_mr));
            adc = SoundIn.ar([0, 1]);
            al = Pan2.ar(adc[0] * In.kr(lvl_al), In.kr(pan_al));
            ar = Pan2.ar(adc[1] * In.kr(lvl_ar), In.kr(pan_ar));
            
            sum = (ml + mr + al + ar) * drive;
            
            sys_age = In.kr(phys_bus + 0) * 10.0;
            age_vcf_l = K2A.ar(LFNoise2.kr(0.0151)) * sys_age * 0.05;
            age_vcf_r = K2A.ar(LFNoise2.kr(0.0163)) * sys_age * 0.05;
            
            filt_l = MoogFF.ar(sum[0], (cut_l * (1.0 + age_vcf_l)).clip(20, 20000), res * 4.0);
            filt_r = MoogFF.ar(sum[1], (cut_r * (1.0 + age_vcf_r)).clip(20, 20000), res * 4.0);
            filt_sig = Select.ar(K2A.ar(filt_byp), [[filt_l, filt_r], sum]);
            
            wow_amt = In.kr(phys_bus + 5);
            flut_amt = In.kr(phys_bus + 6);
            tape_in = filt_sig + (LocalIn.ar(2) * tape_fb);
            
            tape_time_lag = Lag3.kr(tape_time, 0.5);
            wow = OnePole.kr(LFNoise2.kr(Rand(0.5, 2.0)) * wow_amt * 0.05, 0.95);
            flutter = LFNoise1.kr(15) * flut_amt * 0.005;
            tape_dt = (tape_time_lag + wow + flutter).clip(0.01, 2.0);
            
            tape_raw = DelayC.ar(tape_in, 2.2, tape_dt);
            // TAPE HYSTERESIS
            tape_sat_sig = (tape_raw + (Delay1.ar(tape_raw) * 0.2)).tanh;
            
            tape_physics_cutoff = LinExp.kr(tape_time_lag.max(0.01), 0.01, 2.0, 15000, 3000);
            tape_out = LPF.ar(tape_sat_sig, tape_physics_cutoff);
            
            loop_dust_trig = Dust.kr(tape_erosion * 15);
            loop_dropout_env = Decay.kr(loop_dust_trig, 0.1);
            loop_gain_loss = (loop_dropout_env * tape_erosion).clip(0, 0.9);
            tape_out = tape_out * (1.0 - loop_gain_loss);
            
            LocalOut.ar(tape_out); 
            
            master = filt_sig + (tape_out * tape_mix * (1.0 - tape_mute));
            final_out = (master + (adc * adc_mon)) * master_vol;
            
            Out.ar(out_ml, final_out[0] * In.kr(lvl_oml));
            Out.ar(out_mr, final_out[1] * In.kr(lvl_omr));
            Out.ar(out_tl, tape_out[0] * In.kr(lvl_otl));
            Out.ar(out_tr, tape_out[1] * In.kr(lvl_otr));
        }).add;

        context.server.sync;

        // =====================================================================
        // INSTANCIACIÓN DE NODOS
        // =====================================================================
        
        synth_matrix_amps = Synth.new(\Elianne_MatrixAmps,[], context.xg, \addToHead);
        64.do { |i|
            synth_matrix_rows[i] = Synth.new(\Elianne_MatrixRow,[\out_bus, bus_nodes_rx.index + i], context.xg, \addToHead);
        };
        
        synth_mods[0] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+0, \in_fm2, bus_nodes_rx.index+1, \in_pwm, bus_nodes_rx.index+2, \in_voct, bus_nodes_rx.index+3,
            \out_main, bus_nodes_tx.index+4, \out_inv, bus_nodes_tx.index+5, \out_sine, bus_nodes_tx.index+6, \out_pulse, bus_nodes_tx.index+7,
            \lvl_fm1, bus_levels.index+0, \lvl_fm2, bus_levels.index+1, \lvl_pwm, bus_levels.index+2, \lvl_voct, bus_levels.index+3,
            \lvl_main, bus_levels.index+4, \lvl_inv, bus_levels.index+5, \lvl_sine, bus_levels.index+6, \lvl_pulse, bus_levels.index+7,
            \phys_bus, bus_physics.index, \seed_offset, 0.1
        ], context.xg, \addToTail);

        synth_mods[1] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_nodes_rx.index+8, \in_fm2, bus_nodes_rx.index+9, \in_pwm, bus_nodes_rx.index+10, \in_voct, bus_nodes_rx.index+11,
            \out_main, bus_nodes_tx.index+12, \out_inv, bus_nodes_tx.index+13, \out_sine, bus_nodes_tx.index+14, \out_pulse, bus_nodes_tx.index+15,
            \lvl_fm1, bus_levels.index+8, \lvl_fm2, bus_levels.index+9, \lvl_pwm, bus_levels.index+10, \lvl_voct, bus_levels.index+11,
            \lvl_main, bus_levels.index+12, \lvl_inv, bus_levels.index+13, \lvl_sine, bus_levels.index+14, \lvl_pulse, bus_levels.index+15,
            \phys_bus, bus_physics.index, \seed_offset, 0.2
        ], context.xg, \addToTail);

        synth_mods[2] = Synth.new(\Elianne_1023,[
            \in_fm1, bus_nodes_rx.index+16, \in_fm2, bus_nodes_rx.index+17, \in_pv1, bus_nodes_rx.index+18, \in_pv2, bus_nodes_rx.index+19,
            \out_o1, bus_nodes_tx.index+20, \out_o2, bus_nodes_tx.index+21, \out_i1, bus_nodes_tx.index+22, \out_i2, bus_nodes_tx.index+23,
            \lvl_fm1, bus_levels.index+16, \lvl_fm2, bus_levels.index+17, \lvl_pv1, bus_levels.index+18, \lvl_pv2, bus_levels.index+19,
            \lvl_o1, bus_levels.index+20, \lvl_o2, bus_levels.index+21, \lvl_i1, bus_levels.index+22, \lvl_i2, bus_levels.index+23,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        synth_mods[3] = Synth.new(\Elianne_1016,[
            \in_sig, bus_nodes_rx.index+24, \in_clk, bus_nodes_rx.index+25,
            \out_n1, bus_nodes_tx.index+26, \out_n2, bus_nodes_tx.index+27, \out_slow, bus_nodes_tx.index+28, \out_step, bus_nodes_tx.index+29,
            \lvl_sig, bus_levels.index+24, \lvl_clk, bus_levels.index+25,
            \lvl_n1, bus_levels.index+26, \lvl_n2, bus_levels.index+27, \lvl_slow, bus_levels.index+28, \lvl_step, bus_levels.index+29,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        synth_mods[4] = Synth.new(\Elianne_1005,[
            \in_car, bus_nodes_rx.index+30, \in_mod, bus_nodes_rx.index+31, \in_vca, bus_nodes_rx.index+32, \in_gate, bus_nodes_rx.index+33,
            \out_main, bus_nodes_tx.index+34, \out_inv, bus_nodes_tx.index+35, \out_sum, bus_nodes_tx.index+36, \out_diff, bus_nodes_tx.index+37,
            \lvl_car, bus_levels.index+30, \lvl_mod, bus_levels.index+31, \lvl_vca, bus_levels.index+32, \lvl_gate, bus_levels.index+33,
            \lvl_main, bus_levels.index+34, \lvl_inv, bus_levels.index+35, \lvl_sum, bus_levels.index+36, \lvl_diff, bus_levels.index+37,
            \phys_bus, bus_physics.index
        ], context.xg, \addToTail);

        synth_mods[5] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+38, \in_cv1, bus_nodes_rx.index+39, \in_res, bus_nodes_rx.index+40, \in_cv2, bus_nodes_rx.index+41,
            \out_lp, bus_nodes_tx.index+42, \out_bp, bus_nodes_tx.index+43, \out_hp, bus_nodes_tx.index+44, \out_notch, bus_nodes_tx.index+45,
            \lvl_aud, bus_levels.index+38, \lvl_cv1, bus_levels.index+39, \lvl_res, bus_levels.index+40, \lvl_cv2, bus_levels.index+41,
            \lvl_lp, bus_levels.index+42, \lvl_bp, bus_levels.index+43, \lvl_hp, bus_levels.index+44, \lvl_notch, bus_levels.index+45,
            \phys_bus, bus_physics.index, \seed_offset, 0.3
        ], context.xg, \addToTail);

        synth_mods[6] = Synth.new(\Elianne_1047,[
            \in_aud, bus_nodes_rx.index+46, \in_cv1, bus_nodes_rx.index+47, \in_res, bus_nodes_rx.index+48, \in_cv2, bus_nodes_rx.index+49,
            \out_lp, bus_nodes_tx.index+50, \out_bp, bus_nodes_tx.index+51, \out_hp, bus_nodes_tx.index+52, \out_notch, bus_nodes_tx.index+53,
            \lvl_aud, bus_levels.index+46, \lvl_cv1, bus_levels.index+47, \lvl_res, bus_levels.index+48, \lvl_cv2, bus_levels.index+49,
            \lvl_lp, bus_levels.index+50, \lvl_bp, bus_levels.index+51, \lvl_hp, bus_levels.index+52, \lvl_notch, bus_levels.index+53,
            \phys_bus, bus_physics.index, \seed_offset, 0.4
        ], context.xg, \addToTail);

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
        
        this.addCommand("patch_set", "iif", { |msg| 
            var dst = msg[1] - 1; 
            var src = msg[2] - 1;
            var val = msg[3];
            
            matrix_state[dst][src] = val;
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

        // M2
        this.addCommand("m2_tune", "f", { |msg| synth_mods[1].set(\tune, msg[1]) });
        this.addCommand("m2_fine", "f", { |msg| synth_mods[1].set(\fine, msg[1]) });
        this.addCommand("m2_pwm", "f", { |msg| synth_mods[1].set(\pwm_base, msg[1]) });
        this.addCommand("m2_mix_sine", "f", { |msg| synth_mods[1].set(\mix_sine, msg[1]) });
        this.addCommand("m2_mix_tri", "f", { |msg| synth_mods[1].set(\mix_tri, msg[1]) });
        this.addCommand("m2_mix_saw", "f", { |msg| synth_mods[1].set(\mix_saw, msg[1]) });
        this.addCommand("m2_mix_pulse", "f", { |msg| synth_mods[1].set(\mix_pulse, msg[1]) });
        this.addCommand("m2_range", "i", { |msg| synth_mods[1].set(\range, msg[1]) });

        // M3
        this.addCommand("m3_tune1", "f", { |msg| synth_mods[2].set(\tune1, msg[1]) });
        this.addCommand("m3_pwm1", "f", { |msg| synth_mods[2].set(\pwm1, msg[1]) });
        this.addCommand("m3_morph1", "f", { |msg| synth_mods[2].set(\morph1, msg[1]) });
        this.addCommand("m3_range1", "i", { |msg| synth_mods[2].set(\range1, msg[1]) });
        this.addCommand("m3_pv1_mode", "i", { |msg| synth_mods[2].set(\pv1_mode, msg[1]) });
        this.addCommand("m3_tune2", "f", { |msg| synth_mods[2].set(\tune2, msg[1]) });
        this.addCommand("m3_pwm2", "f", { |msg| synth_mods[2].set(\pwm2, msg[1]) });
        this.addCommand("m3_morph2", "f", { |msg| synth_mods[2].set(\morph2, msg[1]) });
        this.addCommand("m3_range2", "i", { |msg| synth_mods[2].set(\range2, msg[1]) });
        this.addCommand("m3_pv2_mode", "i", { |msg| synth_mods[2].set(\pv2_mode, msg[1]) });

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
    }

    free {
        synth_matrix_amps.free;
        synth_matrix_rows.do({ |s| if(s.notNil, { s.free }) });
        synth_mods.do({ |s| if(s.notNil, { s.free }) });
        bus_nodes_tx.free;
        bus_nodes_rx.free;
        bus_levels.free;
        bus_pans.free;
        bus_physics.free;
    }
}
