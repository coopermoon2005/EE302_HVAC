%% analyze_results.m  --  hardware vs simulation, metrics, faults, energy (Req. 2, 4, 5)
% Loads the NEWEST results/hw_*.mat for each controller+scenario, replays the
% same experiment in Simulink (same Ta, reference, controller, plate/bias times),
% and writes tables + figures to results/.
clear; clc; close all;
hvac_params;
load_system('HVAC_Sim');
SETTLE_BAND = 0.5;
f = dir(fullfile('results','hw_*.mat'));
if isempty(f), error('No hardware runs found in results/.'); end

% newest file per (controller, scenario)
key = regexprep({f.name}, '_\d{8}_\d{4}\.mat$', '');
[ukeys, ~, g] = unique(key);
runs = struct();
for i = 1:numel(ukeys)
    idx = find(g == i); [~, j] = max([f(idx).datenum]);
    d = load(fullfile(f(idx(j)).folder, f(idx(j)).name));
    nm = matlab.lang.makeValidName(erase(ukeys{i}, 'hw_'));

    % ----- replay in Simulink -----
    Ta = d.Ta_lat; CTRL = d.ctrl;
    REF_TS = [d.prof(:,1), Ta + d.prof(:,2)];
    AIR_TS = [0 1]; BIAS_TS = [0 0];
    plateA = A_RESTRICT; if strcmp(d.scenario,'fanfail'), plateA = A_BLOCKED; end
    for e = 1:size(d.ev,1)
        switch d.ev(e,2)
            case {1,2}, AIR_TS(end+1,:) = [d.ev(e,1), 1 + d.ev(e,3)*(plateA-1)]; %#ok<SAGROW>
            case 3,     BIAS_TS(end+1,:) = [d.ev(e,1), d.ev(e,3)*SENSOR_BIAS];   %#ok<SAGROW>
        end
    end
    out = sim('HVAC_Sim','StopTime',num2str(d.t(end)));
    lg = out.get('simlog'); ts = out.get('simt');
    d.sim = struct('t',ts(:),'Tm',lg(:,2),'u',lg(:,3));
    runs.(nm) = d;

    % ----- overlay figure -----
    fg = figure('Name',nm,'Position',[60 60 900 650]);
    subplot(3,1,1); hold on; grid on;
    stairs(d.t,d.ref,'k--'); plot(d.t,d.Tm,'b'); plot(d.sim.t,d.sim.Tm,'r');
    for e = 1:size(d.ev,1), xline(d.ev(e,1),':'); end
    legend('Reference','Hardware','Simulation','Location','best'); ylabel('T [\circC]');
    title(strrep(nm,'_','\_'));
    subplot(3,1,2); hold on; grid on;
    stairs(d.t,d.u,'b'); stairs(d.sim.t,d.sim.u,'r'); ylabel('u [V]');
    subplot(3,1,3); hold on; grid on;
    plot(d.t,d.rf,'b'); yline(FD.R_TH,'r--'); yline(-FD.R_TH,'r--');
    k = find(d.flag,1); if ~isempty(k), xline(d.t(k),'r-',d.label{k}); end
    ylabel('r_f [\circC]'); xlabel('t [s]');
    saveas(fg, fullfile('results',['fig_hw_' nm '.png']));
end

%% ----- Req 2: hardware controller comparison (tracking runs) -----
rows = {};
for nm = fieldnames(runs)'
    d = runs.(nm{1});
    if ~strcmp(d.scenario,'track'), continue; end
    p = d.prof;
    for s = 2:size(p,1)
        t1 = d.t(end); if s < size(p,1), t1 = p(s+1,1); end
        for src = {'hw','sim'}
            if strcmp(src{1},'hw'), tt = d.t; yy = d.Tm; else, tt = d.sim.t; yy = d.sim.Tm; end
            mtr = step_metrics(tt, yy, d.Ta_lat+p(s-1,2), d.Ta_lat+p(s,2), p(s,1), t1, SETTLE_BAND);
            rows(end+1,:) = {nm{1}, src{1}, sprintf('%+.1f->%+.1f',p(s-1,2),p(s,2)), mtr.rise_s, ...
                mtr.settle_s, mtr.overshoot_pct, mtr.ess_degC, mtr.ripple_degC}; %#ok<SAGROW>
        end
    end
end
if ~isempty(rows)
    TT = cell2table(rows,'VariableNames',{'run','source','step','rise_s','settle_s', ...
        'overshoot_pct','ess_degC','ripple_degC'});
    disp(TT); writetable(TT, fullfile('results','hw_metrics.csv'));
end

%% ----- Req 4: disturbance recovery -----
for nm = fieldnames(runs)'
    d = runs.(nm{1});
    if ~strcmp(d.scenario,'dist') || isempty(d.ev), continue; end
    t_in = d.ev(find(d.ev(:,2)==1,1),1);
    w = d.t >= t_in & d.t < t_in + 400;
    err = d.Tm(w) - d.ref(w);
    [pk, ip] = max(abs(err)); tw = d.t(w);
    back = find(abs(err) > SETTLE_BAND, 1, 'last');
    rec_t = NaN; if ~isempty(back) && back < numel(tw), rec_t = tw(back+1) - t_in; end
    fprintf('%s: peak deviation %.2f C at +%.0f s, recovered (|e|<%.1f) after %.0f s\n', ...
        nm{1}, pk, tw(ip)-t_in, SETTLE_BAND, rec_t);
end

%% ----- Req 5: fault detection + energy -----
rows = {};
for nm = fieldnames(runs)'
    d = runs.(nm{1});
    tf = NaN; if ~isempty(d.ev), tf = d.ev(1,1); end
    k = find(d.flag,1);
    if isempty(k), tdet = NaN; lab = 'none'; else, tdet = d.t(k); lab = d.label{k}; end
    post = d.t >= max(450, tf + 50); if ~any(post), post = true(size(d.t)); end
    Pavg = mean(d.P(post)); if ~isfinite(Pavg), Pavg = NaN; end
    rows(end+1,:) = {nm{1}, tf, tdet, tdet - tf, lab, mean(abs(d.ref(post)-d.Tm(post))), ...
        mean(d.u(post)), mean(d.u(post))/U_MAX*100, Pavg, d.E_J}; %#ok<SAGROW>
end
FT = cell2table(rows,'VariableNames',{'run','t_fault_s','t_detect_s','delay_s','label', ...
    'mean_abs_err_C','mean_u_V','duty_pct','mean_power_W','energy_J'});
disp(FT); writetable(FT, fullfile('results','hw_faults_energy.csv'));

%% ----- Estimate airflow factor a from restricted runs (to update hvac_params) -----
for nm = fieldnames(runs)'
    d = runs.(nm{1});
    if ~any(strcmp(d.scenario,{'restrict','fanfail'})) || isempty(d.ev), continue; end
    post = d.t > d.ev(1,1) + 200;
    a_est = K * mean(d.u(post)) / mean(d.Tm(post) - d.Ta_lat);
    fprintf('%s: estimated airflow factor a = %.2f  (put in hvac_params.m)\n', nm{1}, a_est);
end
disp('Figures + CSV tables written to results/.');
