%% build_hvac_model.m  --  builds HVAC_Sim.slx from standard Simulink blocks
% Run once (or again after editing). Needs only base Simulink.
%
% Signal flow:
%  Ref ─►(+)─e─► Relay (ON-OFF) ─┐
%        ▲(-)  └► Discrete PI ───┴► Multiport Switch(CTRL) ► Sat[0,U_MAX] ─u─►
%        │                                                                    │
%  Tm ◄─ ZOH ◄─ (+bias) ◄─ sensor lag ◄─ T ◄─ PLANT: tau dT/dt = K u(t-L) - a (T-Ta)
%  Fault detector: nominal model (a=1, no bias) driven by the same u -> That,
%                  residual r = Tm - That -> LPF -> |r_f| > R_TH
clear; clc;
hvac_params;
REF_TS  = [REF_PROFILE(:,1), Ta + REF_PROFILE(:,2)];   %#ok<NASGU> needed at compile
AIR_TS  = [0 1];  BIAS_TS = [0 0];  CTRL = 2;          %#ok<NASGU>

mdl = 'HVAC_Sim';
if bdIsLoaded(mdl), close_system(mdl, 0); end
if exist([mdl '.slx'], 'file'), delete([mdl '.slx']); end
new_system(mdl); open_system(mdl);
set_param(mdl, 'Solver','ode45', 'StopTime','T_END', 'MaxStep','Ts', ...
               'ReturnWorkspaceOutputs','on');

B = @(n) [mdl '/' n];
add = @(lib, n, pos, varargin) add_block(lib, B(n), 'Position', pos, varargin{:});
ln  = @(a, b) add_line(mdl, a, b, 'autorouting', 'on');

%% ---------- Sources ----------
add('simulink/Sources/From Workspace','Ref',[30 40 110 70], 'VariableName','REF_TS', ...
    'Interpolate','off','OutputAfterFinalValue','Holding final value','SampleTime','Ts');
add('simulink/Sources/From Workspace','Airflow a(t)',[30 330 110 360], 'VariableName','AIR_TS', ...
    'Interpolate','off','OutputAfterFinalValue','Holding final value','SampleTime','Ts');
add('simulink/Sources/From Workspace','Sensor bias',[30 470 110 500], 'VariableName','BIAS_TS', ...
    'Interpolate','off','OutputAfterFinalValue','Holding final value','SampleTime','Ts');
add('simulink/Sources/Constant','Ta',[30 400 80 420], 'Value','Ta');
add('simulink/Sources/Constant','CTRL (1=ONOFF 2=PI)',[200 150 260 170], 'Value','CTRL');

%% ---------- Controller ----------
add('simulink/Math Operations/Sum','e',[150 45 170 65], 'Inputs','|+-','IconShape','round');
add('simulink/Discontinuities/Relay','ON-OFF',[230 20 290 50], ...
    'OnSwitchValue','ONOFF.H/2','OffSwitchValue','-ONOFF.H/2', ...
    'OnOutputValue','ONOFF.U_ON','OffOutputValue','0');
add('simulink/Discrete/Discrete PID Controller','PI',[230 80 290 120], ...
    'Controller','PI','P','PI.Kp','I','PI.Ki','SampleTime','Ts', ...
    'LimitOutput','on','UpperSaturationLimit','U_MAX','LowerSaturationLimit','0', ...
    'AntiWindupMode','clamping');
add('simulink/Signal Routing/Multiport Switch','Select',[330 30 360 130], 'Inputs','2');
add('simulink/Discontinuities/Saturation','Sat 0..U_MAX',[400 65 440 95], ...
    'UpperLimit','U_MAX','LowerLimit','0');

ln('Ref/1','e/1');
ln('e/1','ON-OFF/1');  ln('e/1','PI/1');
ln('CTRL (1=ONOFF 2=PI)/1','Select/1');
ln('ON-OFF/1','Select/2'); ln('PI/1','Select/3');
ln('Select/1','Sat 0..U_MAX/1');

%% ---------- Plant ----------
add('simulink/Continuous/Transport Delay','Delay L',[480 200 530 230], 'DelayTime','L', ...
    'InitialOutput','0');
add('simulink/Math Operations/Gain','K',[560 200 600 230], 'Gain','K');
add('simulink/Math Operations/Sum','T-Ta',[560 390 580 410], 'Inputs','|+-','IconShape','round');
add('simulink/Math Operations/Product','a*(T-Ta)',[620 330 650 380]);
add('simulink/Math Operations/Sum','heat balance',[680 200 700 220], 'Inputs','|+-','IconShape','round');
add('simulink/Math Operations/Gain','inv tau',[730 195 770 225], 'Gain','1/tau');
add('simulink/Continuous/Integrator','T (true)',[800 195 830 225], 'InitialCondition','Ta');

ln('Sat 0..U_MAX/1','Delay L/1');
ln('Delay L/1','K/1');
ln('K/1','heat balance/1');
ln('T (true)/1','T-Ta/1');  ln('Ta/1','T-Ta/2');
ln('Airflow a(t)/1','a*(T-Ta)/1'); ln('T-Ta/1','a*(T-Ta)/2');
ln('a*(T-Ta)/1','heat balance/2');
ln('heat balance/1','inv tau/1');
ln('inv tau/1','T (true)/1');

%% ---------- Sensor: first-order lag + bias + sampling ----------
add('simulink/Math Operations/Sum','sens err',[880 200 900 220], 'Inputs','|+-','IconShape','round');
add('simulink/Math Operations/Gain','inv tau_s',[920 195 960 225], 'Gain','1/tau_s');
add('simulink/Continuous/Integrator','sensor',[990 195 1020 225], 'InitialCondition','Ta');
add('simulink/Math Operations/Sum','+bias',[1050 200 1070 220], 'Inputs','|++','IconShape','round');
add('simulink/Discrete/Zero-Order Hold','ZOH Ts',[1100 195 1140 225], 'SampleTime','Ts');

ln('T (true)/1','sens err/1');
ln('sensor/1','sens err/2');
ln('sens err/1','inv tau_s/1');
ln('inv tau_s/1','sensor/1');
ln('sensor/1','+bias/1');  ln('Sensor bias/1','+bias/2');
ln('+bias/1','ZOH Ts/1');
ln('ZOH Ts/1','e/2');                      % feedback

%% ---------- Fault detector: nominal model + residual ----------
add('simulink/Continuous/Transport Delay','Delay L (nom)',[480 560 530 590], 'DelayTime','L','InitialOutput','0');
add('simulink/Math Operations/Gain','K (nom)',[560 560 600 590], 'Gain','K');
add('simulink/Math Operations/Sum','That-Ta',[620 640 640 660], 'Inputs','|+-','IconShape','round');
add('simulink/Math Operations/Sum','nom balance',[680 565 700 585], 'Inputs','|+-','IconShape','round');
add('simulink/Math Operations/Gain','inv tau (nom)',[730 560 770 590], 'Gain','1/tau');
add('simulink/Continuous/Integrator','That',[800 560 830 590], 'InitialCondition','Ta');
add('simulink/Discrete/Zero-Order Hold','ZOH nom',[860 560 900 590], 'SampleTime','Ts');
add('simulink/Math Operations/Sum','residual',[940 565 960 585], 'Inputs','|+-','IconShape','round');
add('simulink/Discrete/Discrete Transfer Fcn','LPF Tf',[990 555 1060 595], ...
    'Numerator','[1-exp(-Ts/FD.Tf)]','Denominator','[1 -exp(-Ts/FD.Tf)]','SampleTime','Ts');
add('simulink/Math Operations/Abs','|r_f|',[1090 560 1120 590]);
add('simulink/Logic and Bit Operations/Compare To Constant','> R_TH',[1150 560 1210 590], ...
    'relop','>','const','FD.R_TH');
add('simulink/Signal Attributes/Data Type Conversion','to double',[1240 560 1290 590], ...
    'OutDataTypeStr','double');

ln('Sat 0..U_MAX/1','Delay L (nom)/1');
ln('Delay L (nom)/1','K (nom)/1');
ln('K (nom)/1','nom balance/1');
ln('That/1','That-Ta/1');  ln('Ta/1','That-Ta/2');
ln('That-Ta/1','nom balance/2');
ln('nom balance/1','inv tau (nom)/1');
ln('inv tau (nom)/1','That/1');
ln('That/1','ZOH nom/1');
ln('ZOH Ts/1','residual/1');  ln('ZOH nom/1','residual/2');
ln('residual/1','LPF Tf/1');
ln('LPF Tf/1','|r_f|/1');
ln('|r_f|/1','> R_TH/1');
ln('> R_TH/1','to double/1');

%% ---------- Logging + scope ----------
% simlog columns: 1 ref | 2 Tm | 3 u | 4 T_true | 5 That | 6 r_f | 7 flag_raw | 8 a
add('simulink/Signal Routing/Mux','log mux',[1340 150 1345 470], 'Inputs','8');
add('simulink/Sinks/To Workspace','simlog',[1380 295 1450 325], ...
    'VariableName','simlog','SaveFormat','Array','SampleTime','Ts');
add('simulink/Sources/Clock','Clock',[1300 520 1320 540]);
add('simulink/Sinks/To Workspace','simt',[1380 515 1450 545], ...
    'VariableName','simt','SaveFormat','Array','SampleTime','Ts');
add('simulink/Signal Routing/Mux','temp mux',[1340 30 1345 80], 'Inputs','2');
add('simulink/Sinks/Scope','Scope',[1390 30 1430 100], 'NumInputPorts','2');

ln('Ref/1','log mux/1');
ln('ZOH Ts/1','log mux/2');
ln('Sat 0..U_MAX/1','log mux/3');
ln('T (true)/1','log mux/4');
ln('ZOH nom/1','log mux/5');
ln('LPF Tf/1','log mux/6');
ln('to double/1','log mux/7');
ln('Airflow a(t)/1','log mux/8');
ln('log mux/1','simlog/1');
ln('Clock/1','simt/1');
ln('Ref/1','temp mux/1');  ln('ZOH Ts/1','temp mux/2');
ln('temp mux/1','Scope/1');  ln('Sat 0..U_MAX/1','Scope/2');

%% ---------- Optional: group into subsystems for a clean report figure ----------
try
    grp = @(names, nm) Simulink.BlockDiagram.createSubsystem( ...
        cellfun(@(n) get_param(B(n),'Handle'), names), 'Name', nm);
    grp({'Delay L','K','T-Ta','a*(T-Ta)','heat balance','inv tau','T (true)'}, 'Thermal Plant');
    grp({'sens err','inv tau_s','sensor','+bias','ZOH Ts'}, 'Sensor');
    grp({'e','ON-OFF','PI','Select','Sat 0..U_MAX'}, 'Controller');
    grp({'Delay L (nom)','K (nom)','That-Ta','nom balance','inv tau (nom)','That','ZOH nom', ...
         'residual','LPF Tf','|r_f|','> R_TH','to double'}, 'Fault Detector');
catch ME
    fprintf('(Subsystem grouping skipped: %s)\nModel is still complete and runnable.\n', ME.message);
end

save_system(mdl);
fprintf('Built %s.slx  ->  now run run_simulations.m\n', mdl);
