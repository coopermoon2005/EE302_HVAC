%% run_simulations.m  --  all simulation results for the report (Req. 1, 2, 4, 5)
% Needs HVAC_Sim.slx (run build_hvac_model.m first).
% Produces: results/sim_*.mat, results/fig_sim_*.png, results/sim_metrics.csv
clear; clc; close all;
hvac_params;
if ~exist('results','dir'), mkdir results; end
load_system('HVAC_Sim');
SETTLE_BAND = 0.5;     % [degC] settling band used for ALL metrics (state it in report)

%% ---------- Scenario list ----------
% name, CTRL, ref profile (delta), airflow [t a], bias [t b], fault time
REF_HOLD = [0 0; 20 5];                       % hold +5 degC for disturbance/fault runs
sc = {
 'onoff_track', 1, REF_PROFILE, [0 1],                                   [0 0],          NaN
 'pi_track',    2, REF_PROFILE, [0 1],                                   [0 0],          NaN
 'onoff_dist',  1, REF_HOLD,    [0 1; 400 A_RESTRICT; 800 1],            [0 0],          400
 'pi_dist',     2, REF_HOLD,    [0 1; 400 A_RESTRICT; 800 1],            [0 0],          400
 'pi_normal',   2, REF_HOLD,    [0 1],                                   [0 0],          NaN
 'pi_restrict', 2, REF_HOLD,    [0 1; 400 A_RESTRICT],                   [0 0],          400
 'pi_fanfail',  2, REF_HOLD,    [0 1; 400 A_BLOCKED],                    [0 0],          400
 'pi_bias',     2, REF_HOLD,    [0 1],                                   [0 0; 400 SENSOR_BIAS], 400
};

R = struct();
for k = 1:size(sc,1)
    [nm, CTRL, prof, AIR_TS, BIAS_TS, tf] = sc{k,:};
    REF_TS = [prof(:,1), Ta + prof(:,2)];
    out  = sim('HVAC_Sim', 'StopTime', num2str(T_END));
    lg   = out.get('simlog');  t = out.get('simt');  t = t(:);
    d = struct('t',t,'ref',lg(:,1),'Tm',lg(:,2),'u',lg(:,3),'T',lg(:,4), ...
               'That',lg(:,5),'rf_sl',lg(:,6),'flag_raw',lg(:,7),'a',lg(:,8), ...
               'Ta',Ta*ones(size(t)),'t_fault',tf,'ctrl',CTRL);
    % same fault-detector code as on hardware
    st = fd_update(); d.flag = false(size(t)); d.rf = zeros(size(t)); d.label = cell(size(t));
    for i = 1:numel(t)
        [st, d.flag(i), d.label{i}] = fd_update(st, t(i), d.Tm(i), d.That(i), d.u(i), NaN, FD, Ts);
        d.rf(i) = st.rf;
    end
    d.E_us  = sum(d.u) * Ts;                 % actuator effort [V*s]
    d.duty  = mean(d.u) / U_MAX * 100;       % [% of max]
    R.(nm) = d;
    save(fullfile('results',['sim_' nm '.mat']), '-struct', 'd');
    fprintf('done: %s\n', nm);
end

%% ---------- Req 2: controller comparison table ----------
rows = {}; 
for nm = {'onoff_track','pi_track'}
    d = R.(nm{1});
    steps = REF_PROFILE;  
    for s = 2:size(steps,1)
        t0 = steps(s,1); 
        if s < size(steps,1), t1 = steps(s+1,1); else, t1 = T_END; end
        m = step_metrics(d.t, d.Tm, Ta+steps(s-1,2), Ta+steps(s,2), t0, t1, SETTLE_BAND);
        rows(end+1,:) = {nm{1}, sprintf('%+.1f->%+.1f',steps(s-1,2),steps(s,2)), ...
            m.rise_s, m.settle_s, m.overshoot_pct, m.ess_degC, m.ripple_degC, d.E_us, d.duty}; %#ok<SAGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'run','step_degC','rise_s','settle_s', ...
    'overshoot_pct','ess_degC','ripple_degC','effort_Vs','duty_pct'});
disp(T); writetable(T, fullfile('results','sim_metrics.csv'));

%% ---------- Figures ----------
f = figure('Name','Sim: ON-OFF vs PI','Position',[50 50 900 600]);
subplot(2,1,1); hold on; grid on;
plot(R.pi_track.t, R.pi_track.ref,'k--','LineWidth',1.2);
plot(R.onoff_track.t, R.onoff_track.Tm,'r'); plot(R.pi_track.t, R.pi_track.Tm,'b');
ylabel('Temperature [\circC]'); legend('Reference','ON-OFF','PI','Location','best');
title('Simulation: setpoint tracking');
subplot(2,1,2); hold on; grid on;
stairs(R.onoff_track.t, R.onoff_track.u,'r'); stairs(R.pi_track.t, R.pi_track.u,'b');
ylabel('Heater command u [V]'); xlabel('Time [s]'); legend('ON-OFF','PI');
saveas(f, fullfile('results','fig_sim_tracking.png'));

f = figure('Name','Sim: disturbance','Position',[80 80 900 600]);
subplot(2,1,1); hold on; grid on;
plot(R.pi_dist.t, R.pi_dist.ref,'k--'); plot(R.onoff_dist.t,R.onoff_dist.Tm,'r'); plot(R.pi_dist.t,R.pi_dist.Tm,'b');
xline(400,':','restrictor in'); xline(800,':','restrictor out');
ylabel('Temperature [\circC]'); legend('Ref','ON-OFF','PI'); title('Simulation: airflow disturbance');
subplot(2,1,2); hold on; grid on;
stairs(R.onoff_dist.t,R.onoff_dist.u,'r'); stairs(R.pi_dist.t,R.pi_dist.u,'b');
ylabel('u [V]'); xlabel('Time [s]');
saveas(f, fullfile('results','fig_sim_disturbance.png'));

f = figure('Name','Sim: faults','Position',[110 110 900 700]);
names = {'pi_normal','pi_restrict','pi_fanfail','pi_bias'}; cols = {'k','m','r','b'};
subplot(3,1,1); hold on; grid on;
for i=1:4, plot(R.(names{i}).t, R.(names{i}).Tm, cols{i}); end
ylabel('T_m [\circC]'); legend(strrep(names,'_','\_')); title('Simulation: normal vs faulted (fault at 400 s)');
subplot(3,1,2); hold on; grid on;
for i=1:4, plot(R.(names{i}).t, R.(names{i}).rf, cols{i}); end
yline(FD.R_TH,'--'); yline(-FD.R_TH,'--'); ylabel('filtered residual [\circC]');
subplot(3,1,3); hold on; grid on;
for i=1:4, stairs(R.(names{i}).t, R.(names{i}).u, cols{i}); end
ylabel('u [V]'); xlabel('Time [s]');
saveas(f, fullfile('results','fig_sim_faults.png'));

%% ---------- Req 5: fault detection + energy table ----------
rows = {};
for i = 1:numel(names)
    d = R.(names{i});
    k = find(d.flag, 1);
    if isempty(k), tdet = NaN; lab = 'none'; else, tdet = d.t(k); lab = d.label{k}; end
    post = d.t >= 450;                                % after fault settles
    rows(end+1,:) = {names{i}, tdet, tdet - d.t_fault, lab, ...
        mean(abs(d.ref(post)-d.Tm(post))), d.E_us, d.duty}; %#ok<SAGROW>
end
F = cell2table(rows,'VariableNames',{'run','t_detect_s','delay_s','label', ...
    'mean_abs_err_degC','effort_Vs','duty_pct'});
disp(F); writetable(F, fullfile('results','sim_faults.csv'));
