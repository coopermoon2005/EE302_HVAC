%% hw_check_io.m  --  FIRST thing to run on the hardware
% 1) finds the ELVIS, 2) reads sensors in both terminal modes,
% 3) optional short heater pulse to verify AO1 -> heater -> temperature rise.
clear; clc;
hvac_params;

%% 1+2. Sensors in both terminal configurations
modes = {'SingleEnded','Differential'};
for i = 1:2
    HW.term_cfg = modes{i};
    try
        [dIn, dOut, HW] = hw_open(HW);
        fprintf('\n--- TerminalConfig = %s ---\n', modes{i});
        fprintf('   Tc[C]   Ta[C]   I[A]    Vh[V]   | raw AI5  AI7  AI1  AI3 [V]\n');
        for k = 1:10
            m = hw_read(dIn, HW);
            fprintf('  %6.2f  %6.2f  %6.3f  %6.2f  | %6.3f %6.3f %6.3f %6.3f\n', ...
                m.Tc, m.Ta, m.I, m.Vh, m.raw);
            pause(0.5);
        end
        clear dIn dOut;
    catch ME
        fprintf('Mode %s failed: %s\n', modes{i}, ME.message);
    end
end
fprintf(['\nPICK the mode where Tc and Ta are both 15-35 C, within ~1-2 C of each other,\n' ...
         'and steady (heater off, fan running). Put it in hvac_params.m -> HW.term_cfg.\n' ...
         'If both read ~0: Prototyping Board Power switch is OFF.\n' ...
         'If values look wrong in both: see QNET manual section 3.6 (thermistor offset pots).\n\n']);

%% 3. Heater pulse test
if ~strcmpi(input('Run 30 s heater test at AO1 = 3 V? (y/n): ','s'), 'y'), return; end
HW.term_cfg = input('Terminal mode to use (SingleEnded/Differential): ','s');
[dIn, dOut, HW] = hw_open(HW);
cleanup = onCleanup(@() write(dOut, 0));     %#ok<NASGU> heater off no matter what
u = 3;
write(dOut, u);
fprintf('Heater ON at %.1f V (expect amplifier ~%.1f V)\n', u, HW.amp_gain*u);
tic;
while toc < 30
    m = hw_read(dIn, HW);
    fprintf('t=%4.1fs  Tc=%6.2f  Ta=%6.2f  I=%5.3f A  Vh=%5.2f V  P=%5.2f W\n', ...
        toc, m.Tc, m.Ta, m.I, m.Vh, m.I*m.Vh);
    if m.Tc > T_ABS_MAX, disp('Over-temperature! stopping'); break; end
    pause(1);
end
write(dOut, 0);
disp('PASS if: Tc rose by about 2-3 degC, Vh is near 2.3 x AO1 (about 6.9 V), I is about Vh/29.5 ohm.');
disp('If Vh/I are off, energy falls back to the u-based proxy; tell me the numbers and I will fix k_V/k_I.');
