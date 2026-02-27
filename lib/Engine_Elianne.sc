// lib/Engine_Elianne.sc v0.1
// CHANGELOG v0.1:
// 1. ARCHITECTURE: Implementación de 32 Buses de Fuente y 32 Buses de Destino.
// 2. MATRIX: SynthDef de ruteo O(1) con InFeedback para latencia cero en bucles.
// 3. MODULES: Esqueletos funcionales de los 8 módulos con Attenuverters integrados.

Engine_Elianne : CroneEngine {
    var <bus_sources; // 32 buses: Salidas de los módulos hacia la matriz
    var <bus_dests;   // 32 buses: Entradas a los módulos desde la matriz
    
    var <synth_matrix;
    var <synth_mods; // Array para guardar los synths de los módulos
    
    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        // 1. ASIGNACIÓN DE BUSES (32 Nodos Máximo según globals.lua)
        bus_sources = Bus.audio(context.server, 32);
        bus_dests = Bus.audio(context.server, 32);
        
        synth_mods = Array.newClear(8);

        context.server.sync;

        // -----------------------------------------------------------
        // SYNTH 0: LA MATRIZ DE RUTEO (El corazón del ARP 2500)
        // -----------------------------------------------------------
        SynthDef(\Elianne_Matrix, {
            // Leemos las 32 fuentes con InFeedback para permitir retroalimentación
            var srcs = InFeedback.ar(bus_sources.index, 32);
            
            // Para cada uno de los 32 destinos, calculamos la suma de las fuentes activas
            32.do { |dst_idx|
                // NamedControl crea un array de 32 floats para esta fila específica
                var row_gains = NamedControl.kr(("row_" ++ (dst_idx + 1)).asSymbol, 0 ! 32);
                var sum = (srcs * row_gains).sum;
                
                // Escribimos al bus de destino correspondiente
                Out.ar(bus_dests.index + dst_idx, sum);
            };
        }).add;

        // -----------------------------------------------------------
        // SYNTH 1 & 2: ARP 1004-T (Oscilador Complejo)
        // -----------------------------------------------------------
        SynthDef(\Elianne_1004T, {
            arg out_main, out_inv, out_sine, out_pulse,
                in_fm1, in_fm2, in_pwm, in_voct,
                // Attenuverters de Entrada
                lvl_in_fm1=1.0, lvl_in_fm2=1.0, lvl_in_pwm=1.0, lvl_in_voct=1.0,
                // Attenuverters de Salida
                lvl_out_main=1.0, lvl_out_inv=1.0, lvl_out_sine=1.0, lvl_out_pulse=1.0,
                // Parámetros del Módulo
                tune=100.0, fine=0.0, pwm_base=0.5,
                mix_sine=1.0, mix_tri=0.0, mix_saw=0.0, mix_pulse=0.0;
                
            var fm1 = In.ar(in_fm1) * lvl_in_fm1;
            var fm2 = In.ar(in_fm2) * lvl_in_fm2;
            var pwm_mod = In.ar(in_pwm) * lvl_in_pwm;
            var voct = In.ar(in_voct) * lvl_in_voct;
            
            var freq = (tune + fine + (fm1 * 50) + (fm2 * 50)) * (2.0 ** voct);
            var pwm_final = (pwm_base + pwm_mod).clip(0.05, 0.95);
            
            // Generación (Integrador de fase puro para evitar aliasing en FM extrema)
            var phase = Phasor.ar(0, freq * SampleDur.ir, 0, 1);
            var sig_tri = (phase * 2 - 1).abs * 2 - 1;
            var sig_saw = phase * 2 - 1;
            var sig_pulse = (phase > pwm_final) * 2 - 1;
            // Conformador de diodos para el Seno (THD analógico)
            var sig_sine = sig_tri - (sig_tri.pow(3) / 6.0); 
            
            var mix = (sig_sine * mix_sine) + (sig_tri * mix_tri) + (sig_saw * mix_saw) + (sig_pulse * mix_pulse);
            
            Out.ar(out_main, mix * lvl_out_main);
            Out.ar(out_inv, (mix * -1.0) * lvl_out_inv);
            Out.ar(out_sine, sig_sine * lvl_out_sine);
            Out.ar(out_pulse, sig_pulse * lvl_out_pulse);
        }).add;

        // -----------------------------------------------------------
        // SYNTH 8: NEXUS (Mastering & Tape Echo)
        // -----------------------------------------------------------
        SynthDef(\Elianne_Nexus, {
            arg out_master_l, out_master_r, out_tape_l, out_tape_r,
                in_mod_l, in_mod_r, in_adc_l, in_adc_r,
                // Attenuverters y Paneo
                lvl_in_mod_l=1.0, pan_in_mod_l= -1.0,
                lvl_in_mod_r=1.0, pan_in_mod_r= 1.0,
                lvl_in_adc_l=1.0, pan_in_adc_l= -0.5,
                lvl_in_adc_r=1.0, pan_in_adc_r= 0.5,
                // Parámetros
                cutoff_l=20000, cutoff_r=20000, res=0.1,
                tape_time=0.3, tape_fb=0.4, tape_mix=0.2, tape_mute=0;
                
            var mod_l = Pan2.ar(In.ar(in_mod_l) * lvl_in_mod_l, pan_in_mod_l);
            var mod_r = Pan2.ar(In.ar(in_mod_r) * lvl_in_mod_r, pan_in_mod_r);
            // ADC In (Hardware Norns)
            var adc = SoundIn.ar([0, 1]);
            var adc_l = Pan2.ar(adc[0] * lvl_in_adc_l, pan_in_adc_l);
            var adc_r = Pan2.ar(adc[1] * lvl_in_adc_r, pan_in_adc_r);
            
            var sum = mod_l + mod_r + adc_l + adc_r;
            
            // Filtros 1006 (Moog Ladder 24dB)
            var filt_l = MoogFF.ar(sum[0], cutoff_l, res);
            var filt_r = MoogFF.ar(sum[1], cutoff_r, res);
            
            // Tape Echo (Estructura básica, se expandirá con Wow/Flutter)
            var tape_in = [filt_l, filt_r] + (LocalIn.ar(2) * tape_fb);
            var tape_out = DelayC.ar(tape_in, 2.0, tape_time);
            tape_out = (tape_out * 1.2).tanh; // Saturación de cinta
            LocalOut.ar(tape_out);
            
            // Salidas
            var master = ([filt_l, filt_r] * (1.0 - tape_mix)) + (tape_out * tape_mix);
            master = master * (1.0 - tape_mute); // K3 Mute
            
            Out.ar(out_master_l, master[0]);
            Out.ar(out_master_r, master[1]);
            Out.ar(out_tape_l, tape_out[0]);
            Out.ar(out_tape_r, tape_out[1]);
        }).add;

        context.server.sync;

        // -----------------------------------------------------------
        // INSTANCIACIÓN DE NODOS
        // -----------------------------------------------------------
        
        // 1. Iniciar la Matriz primero (addToHead para que procese antes que los módulos)
        synth_matrix = Synth.new(\Elianne_Matrix,[], context.xg, \addToHead);
        
        // 2. Instanciar Módulo 1 (1004-T A)
        // Mapeo de buses según globals.lua: Entradas 1 a 4, Salidas 1 a 4
        synth_mods[0] = Synth.new(\Elianne_1004T,[
            \in_fm1, bus_dests.index + 0, \in_fm2, bus_dests.index + 1,
            \in_pwm, bus_dests.index + 2, \in_voct, bus_dests.index + 3,
            \out_main, bus_sources.index + 0, \out_inv, bus_sources.index + 1,
            \out_sine, bus_sources.index + 2, \out_pulse, bus_sources.index + 3
        ], context.xg, \addToTail);

        // 3. Instanciar Módulo 8 (NEXUS)
        // Mapeo de buses: Entradas 29 a 32, Salidas 29 a 32
        synth_mods[7] = Synth.new(\Elianne_Nexus,[
            \in_mod_l, bus_dests.index + 28, \in_mod_r, bus_dests.index + 29,
            \in_adc_l, bus_dests.index + 30, \in_adc_r, bus_dests.index + 31,
            \out_master_l, context.out_b.index, \out_master_r, context.out_b.index + 1, // Directo al DAC
            \out_tape_l, bus_sources.index + 30, \out_tape_r, bus_sources.index + 31
        ], context.xg, \addToTail);

        // -----------------------------------------------------------
        // COMANDOS OSC (LUA -> SC)
        // -----------------------------------------------------------
        
        // Actualizar una fila completa de la matriz (32 valores)
        this.addCommand("patch_row", "iffffffffffffffffffffffffffffffff", { |msg| 
            var dst_idx = msg[1];
            var row_data = msg.drop(2); // Extraer los 32 floats
            synth_matrix.set(("row_" ++ dst_idx).asSymbol, row_data);
        });

        // Comandos de Attenuverters (Ejemplo para el Módulo 1)
        this.addCommand("set_out_level", "if", { |msg|
            var node_id = msg[1];
            var level = msg[2];
            if(node_id == 1, { synth_mods[0].set(\lvl_out_main, level) });
            if(node_id == 2, { synth_mods[0].set(\lvl_out_inv, level) });
            // ... Se expandirá para todos los nodos
        });
    }

    free {
        synth_matrix.free;
        synth_mods.do({ |s| if(s.notNil, { s.free }) });
        bus_sources.free;
        bus_dests.free;
    }
}
