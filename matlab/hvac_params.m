%% hvac_params.m  --  ONE place for every number in the project
% EE302 PS4: Smart HVAC temperature control on Quanser QNET-HVACT + NI ELVIS II+
% Run this first (every other script calls it automatically).
%
% Plant model (first order, ambient-referenced, with dead time):
%       tau * dT/dt = K * u(t - L) - a(t) * (T - Ta)
%   T  : chamber temperature [degC]        Ta : ambient temperature [degC]
%   u  : heater command = AO1 voltage [V]  K  : steady-state gain [degC/V]
%   tau: time constant [s]                 L  : dead time [s]
%   a  : airflow factor (1 = normal; <1 = restricted airflow -> less heat removed)
%
% K, tau, L below are STARTING GUESSES. After running hw_step_test.m and
% identify_model.m, the fitted values are saved in hvac_identified.mat and
% loaded automatically here.

%% ---------------- Hardware / DAQ ----------------
HW.device      = '';            % '' = auto-detect the ELVIS II+ (else e.g. 'Dev1')
HW.ch_heat     = 'ao1';         % heater command (found by scan; ao0 does nothing on this board)
HW.ch_Ic       = 'ai1';         % heater current sense  (PROVISIONAL, check in hw_check_io)
HW.ch_Vh       = 'ai3';         % heater voltage sense  (PROVISIONAL, inverted: reads about -3 V at AO1 = 5 V)
HW.ch_Tc       = 'ai5';         % chamber temperature (ai6 tracks it)
HW.ch_Ta       = 'ai7';         % ambient temperature
HW.term_cfg    = 'Differential'; % set from hw_check_io.m result ('SingleEnded' or 'Differential')
HW.k_T         = 20.0;          % degC per volt (thermistors)
HW.Tc_off      = 1.9;           % [degC] chamber thermistor offset vs ambient (heater off, fan on)
HW.k_I         = -0.22;         % A per volt (provisional: gives about 0.34 A at AO1 = 5 V)
HW.k_V         = -3.33;         % heater V per measured V (negative: sense is inverted)
HW.amp_gain    = 2.0;           % heater volts per AO1 volt (provisional)
HW.n_avg       = 5;             % on-demand samples averaged per control step (noise)

%% ---------------- Safety ----------------
U_MAX     = 5.0;    % [V] max AO1 command (5 V tested for 60 s; do not raise)
T_ABS_MAX = 45;     % [degC] hard cut-off, heater forced off above this
DT_MAX    = 20;     % [degC] heater forced off if T > Ta + DT_MAX

%% ---------------- Timing ----------------
Ts     = 0.5;       % [s] control / sampling period (thermal tau is minutes)
T_END  = 1200;      % [s] default experiment length

%% ---------------- Model (initial guesses) ----------------
K     = 1.3;        % [degC/V]
tau   = 20;         % [s]
L     = 1;          % [s] dead time
Ta    = 24;         % [degC] ambient for simulation (hardware uses measured AI7)
tau_s = 1.0;        % [s] sensor lag (manual: ~4 s settling)
if exist('hvac_identified.mat','file')
    S = load('hvac_identified.mat');
    K = S.K; tau = S.tau; L = S.L;
    fprintf('hvac_params: using identified model K=%.3f degC/V, tau=%.1f s, L=%.1f s\n', K, tau, L);
else
    fprintf('hvac_params: using DEFAULT model guesses (run identify_model.m after a step test)\n');
end
L = max(L, Ts);     % dead time at least one sample (Transport Delay needs > 0)

%% ---------------- Controllers ----------------
% ON-OFF with hysteresis band H around the setpoint
ONOFF.H    = 0.6;          % [degC] total hysteresis width
ONOFF.U_ON = U_MAX;        % heater command when ON

% PI tuned by SIMC rules from (K, tau, L).  tc = desired closed-loop time constant
PI.tc = max(tau/4, 2*L);
PI.Kp = tau / (K * (PI.tc + L));
PI.Ti = min(tau, 4 * (PI.tc + L));
PI.Ki = PI.Kp / PI.Ti;
% (Override by hand here if you want, e.g. PI.Kp = 1.2; PI.Ki = 0.01;)
% Gains fixed to the values used in hardware run 2 (tuned from the step-test model
% K=1.709, tau=33.7, L=0.5), so the refit model only changes the fault detector.
PI.Kp = 33.727 / (1.7087 * (33.727/4 + 0.5));
PI.Ti = 33.727;
PI.Ki = PI.Kp / PI.Ti;

%% ---------------- Reference profile (relative to ambient) ----------------
% [time_s, setpoint_above_ambient_degC] ; held between rows (staircase)
REF_PROFILE = [   0  0
                 20  4
                420  6
                820  3 ];
% Keep every step below K*U_MAX - 1 degC, otherwise it is not reachable.

%% ---------------- Disturbance / fault scenarios ----------------
% Airflow factor a(t): 1 = normal; values below were estimated from the hardware runs
% (analyze_results.m prints the estimate after the restrict / fanfail runs).
A_NORMAL    = 1.00;
A_RESTRICT  = 0.36;   % 50% open plate (disturbance test / restricted-airflow fault); was 0.60, estimated from hw run 6
A_BLOCKED   = 0.18;   % 0% open plate  (fan-failure emulation); was 0.25, estimated from hw run 7
SENSOR_BIAS = 2.0;    % [degC] software bias added to measured temperature

%% ---------------- Fault detector ----------------
FD.Tf      = 20;      % [s] residual low-pass filter time constant
FD.R_TH    = 1.3;     % [degC] threshold on |filtered residual| (normal runs peak ~0.9 with refit model)
FD.T_HOLD  = 15;      % [s] residual must stay above threshold this long
FD.T_ARM   = 60;      % [s] detector disabled during first seconds
FD.JUMP_TH = 1.0;     % [degC/sample] sudden jump in measurement => sensor fault
FD.I_MIN   = 0.05;    % [A] heater current below this while u>0.5 V => heater fault
