%% hw_run_control.m  --  REAL-TIME closed-loop control on QNET-HVACT (Req. 3, 4, 5)
% Edit the three lines in "RUN SETTINGS", run, follow the prompts in the figure title.
% Keys (click the figure first):
%   d = disturbance plate IN/OUT (toggle, logs the time)
%   f = fault plate IN/OUT       (toggle, logs the time)
%   b = software sensor bias ON/OFF (adds SENSOR_BIAS to measured temperature)
%   q = stop (heater goes to 0 V)
clear; clc; close all;
hvac_params;

%% ================= RUN SETTINGS =================
CTRL     = 2;          % 1 = ON-OFF, 2 = PI
SCENARIO = 'dist';        % 'track' | 'dist' | 'normal' | 'restrict' | 'fanfail' | 'bias'
RUN_T    = T_END;      % [s] duration
AUTO_BIAS_T = 400;     % [s] 'bias' scenario: bias switches on by itself at this time (Inf = press b by hand)
%% ================================================
% Unattended runs: settings can come from environment variables, e.g.
%   setenv('HVAC_CTRL','2'); setenv('HVAC_SCENARIO','normal'); hw_run_control
if ~isempty(getenv('HVAC_CTRL')),     CTRL     = str2double(getenv('HVAC_CTRL')); end
if ~isempty(getenv('HVAC_SCENARIO')), SCENARIO = getenv('HVAC_SCENARIO');         end
switch SCENARIO
    case 'track', prof = REF_PROFILE;
    otherwise,    prof = [0 0; 20 5];     % hold +5 degC; insert plate / bias at ~400 s
end
hint = struct('track','Just watch.', ...
              'dist','At ~400 s put 50%% plate on fan, press d. At ~800 s remove, press d.', ...
              'normal','Do nothing (baseline for fault comparison).', ...
              'restrict','At ~400 s put 50%% plate on fan, press f. Leave it.', ...
              'fanfail','At ~400 s put 0%% (closed) plate on fan, press f. Leave it.', ...
              'bias','Sensor bias switches on by itself at AUTO_BIAS_T (or press b).');
CNAME = {'ON-OFF','PI'};
fprintf('Scenario %s, controller %s. %s\n', SCENARIO, CNAME{CTRL}, sprintf(hint.(SCENARIO)));

[dIn, dOut, HW] = hw_open(HW);
cleanup = onCleanup(@() write(dOut, 0)); %#ok<NASGU>
if ~exist('results','dir'), mkdir results; end

%% Latch ambient (like Quanser's "Calibrate" button)
for i = 1:10, m = hw_read(dIn, HW); amb(i) = m.Ta; tc0(i) = m.Tc; pause(0.2); end %#ok<SAGROW>
Ta_lat = mean(amb);
fprintf('Ambient latched: %.2f C   chamber now: %.2f C\n', Ta_lat, mean(tc0));
if abs(mean(tc0) - Ta_lat) > 2
    warning('Chamber is %.1f C away from ambient. Let it cool (fan on, heater off) first.', mean(tc0)-Ta_lat);
end
refAt = @(tt) Ta_lat + prof(find(prof(:,1) <= tt, 1, 'last'), 2);
% Detector model rests at the chamber's own starting reading, not the ambient sensor:
% the heater-off chamber-ambient gap varies between sessions (-0.2 to +1.0 C seen),
% and using Ta_lat turned that gap into a false residual. Start runs from a cooled chamber.
T_rest = mean(tc0);

%% Figure + keys
fig = figure('Name','HVAC real-time (keys: d f b q)','Position',[60 60 1000 720]);
setappdata(fig,'key','');
set(fig,'KeyPressFcn',@(s,e) setappdata(s,'key',e.Key));
a1 = subplot(3,1,1); hold(a1,'on'); grid(a1,'on'); ylabel(a1,'T [\circC]');
hR = stairs(a1,NaN,NaN,'k--'); hT = plot(a1,NaN,NaN,'b'); hH = plot(a1,NaN,NaN,'m:');
legend(a1,'Reference','Measured','Model T\_hat','Location','northwest');
a2 = subplot(3,1,2); hold(a2,'on'); grid(a2,'on'); ylabel(a2,'u [V]');
hU = stairs(a2,NaN,NaN,'r'); ylim(a2,[-0.1 U_MAX+0.2]);
a3 = subplot(3,1,3); hold(a3,'on'); grid(a3,'on'); ylabel(a3,'r_f [\circC]'); xlabel(a3,'t [s]');
hF = plot(a3,NaN,NaN,'b'); yline(a3,FD.R_TH,'r--'); yline(a3,-FD.R_TH,'r--');

%% State
N = ceil(RUN_T/Ts) + 1;
rec = nan(N, 15);   % t ref Tm Tc_raw Ta u I Vh That rf flag bias dist fault safety
lab = repmat({''}, N, 1);
ev  = zeros(0,3);   % [t type state] type 1=dist 2=fault 3=bias
onoff_state = 0; I_int = 0;
bias_on = 0; dist_on = 0; fault_on = 0;
dL = max(round(L/Ts),1); ubuf = zeros(dL,1);
That = mean(tc0); st = fd_update(); last_label = 'OK';

t0 = tic; k = 0;
while true
    k = k + 1; tk = (k-1)*Ts;
    if tk > RUN_T || ~isvalid(fig), break; end
    while toc(t0) < tk, pause(0.002); end

    % ---- keys ----
    key = getappdata(fig,'key'); setappdata(fig,'key','');
    if strcmp(SCENARIO,'bias') && ~bias_on && isempty(ev) && tk >= AUTO_BIAS_T, key = 'b'; end
    switch key
        case 'q', break;
        case 'd', dist_on  = ~dist_on;  ev(end+1,:) = [tk 1 dist_on];  fprintf('%6.1f s  disturbance %d\n', tk, dist_on);
        case 'f', fault_on = ~fault_on; ev(end+1,:) = [tk 2 fault_on]; fprintf('%6.1f s  fault plate %d\n', tk, fault_on);
        case 'b', bias_on  = ~bias_on;  ev(end+1,:) = [tk 3 bias_on];  fprintf('%6.1f s  sensor bias %d\n', tk, bias_on);
    end

    % ---- measure ----
    try
        m = hw_read(dIn, HW);
    catch ME
        write(dOut, 0); warning('Read failed: %s', ME.message); break;
    end
    Tm = m.Tc + bias_on * SENSOR_BIAS;     % what the controller "sees"
    r  = refAt(tk);
    e  = r - Tm;

    % ---- control ----
    if CTRL == 1
        if e > ONOFF.H/2, onoff_state = 1; elseif e < -ONOFF.H/2, onoff_state = 0; end
        u = onoff_state * ONOFF.U_ON;
    else
        u_uns = PI.Kp * e + I_int;
        u = min(max(u_uns, 0), U_MAX);
        if ~((u_uns > U_MAX && e > 0) || (u_uns < 0 && e < 0))   % clamping anti-windup
            I_int = I_int + PI.Ki * Ts * e;
        end
    end

    % ---- safety (uses the RAW sensor, never the biased one) ----
    safety = (m.Tc > T_ABS_MAX) || (m.Tc > Ta_lat + DT_MAX);
    if safety, u = 0; end
    write(dOut, u);

    % ---- nominal model + fault detector ----
    u_del = ubuf(1); ubuf = [ubuf(2:end); u];
    That = That + Ts/tau * (K*u_del - (That - T_rest));
    [st, flag, label] = fd_update(st, tk, Tm, That, u, m.I, FD, Ts);
    if ~strcmp(label, last_label), fprintf('%6.1f s  DETECTOR: %s\n', tk, label); last_label = label; end

    rec(k,:) = [tk r Tm m.Tc m.Ta u m.I m.Vh That st.rf flag bias_on dist_on fault_on safety];
    lab{k} = label;

    % ---- plot (every 2 s) ----
    if mod(k, 4) == 0
        x = rec(1:k,1);
        set(hR,'XData',x,'YData',rec(1:k,2)); set(hT,'XData',x,'YData',rec(1:k,3));
        set(hH,'XData',x,'YData',rec(1:k,9)); set(hU,'XData',x,'YData',rec(1:k,6));
        set(hF,'XData',x,'YData',rec(1:k,10));
        sc_txt = ''; if safety, sc_txt = '  SAFETY CUT'; end
        title(a1, sprintf('%s | %s | t=%.0f/%.0f s | Tm=%.2f r=%.2f | %s%s', SCENARIO, ...
            CNAME{CTRL}, tk, RUN_T, Tm, r, label, sc_txt), 'Interpreter','none');
        if flag, set(a3,'Color',[1 0.9 0.9]); else, set(a3,'Color','w'); end
        drawnow limitrate;
    end
end
write(dOut, 0);
disp('Heater OFF.');

%% Save
ok = ~isnan(rec(:,1)); rec = rec(ok,:); lab = lab(ok);
d = struct('t',rec(:,1),'ref',rec(:,2),'Tm',rec(:,3),'Tc',rec(:,4),'Ta',rec(:,5), ...
    'u',rec(:,6),'I',rec(:,7),'Vh',rec(:,8),'That',rec(:,9),'rf',rec(:,10), ...
    'flag',logical(rec(:,11)),'bias',rec(:,12),'dist',rec(:,13),'fault',rec(:,14), ...
    'safety',rec(:,15));
d.label = lab; d.ev = ev; d.ctrl = CTRL; d.scenario = SCENARIO; d.prof = prof;
d.Ta_lat = Ta_lat; d.T_rest = T_rest; d.Ts = Ts; d.params = struct('K',K,'tau',tau,'L',L,'PI',PI,'ONOFF',ONOFF,'FD',FD,'U_MAX',U_MAX);
d.P = d.Vh .* d.I;                       % heater electrical power [W]
d.E_J = sum(d.P) * Ts;                   % heater energy [J]
d.E_us = sum(d.u) * Ts;  d.duty = mean(d.u) / U_MAX * 100;
cname = {'onoff','pi'};
fn = fullfile('results', sprintf('hw_%s_%s_%s', cname{CTRL}, SCENARIO, datestr(now,'yyyymmdd_HHMM')));
save([fn '.mat'], '-struct', 'd');
writetable(table(d.t,d.ref,d.Tm,d.Tc,d.Ta,d.u,d.I,d.Vh,d.That,d.rf,d.flag,d.label, ...
    'VariableNames',{'t_s','ref_C','Tmeas_C','Traw_C','Tamb_C','u_V','I_A','Vh_V','That_C','rf_C','fault','label'}), [fn '.csv']);
saveas(fig, [fn '.png']);
fprintf('Saved %s.(mat|csv|png)\nEnergy %.0f J, effort %.0f V*s, duty %.1f %%\n', fn, d.E_J, d.E_us, d.duty);
