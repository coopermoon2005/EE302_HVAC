%% hw_step_test.m  --  open-loop heater step for system identification (Req. 1)
% Profile: 60 s heater OFF (baseline) -> U_STEP for 300 s -> OFF for 240 s.
% Start with the chamber at room temperature (fan running >= 2 min, heater off).
clear; clc; close all;
hvac_params;
U_STEP = min(3.0, U_MAX); % [V] step size
T_PRE = 60; T_ON = 300; T_POST = 240;
TT = T_PRE + T_ON + T_POST;

[dIn, dOut, HW] = hw_open(HW);
cleanup = onCleanup(@() write(dOut, 0)); %#ok<NASGU>
if ~exist('results','dir'), mkdir results; end

N = ceil(TT/Ts) + 1;
rec = nan(N, 7);   % t u Tc Ta I Vh safety
fig = figure('Name','Step test (close window to abort)');
ax1 = subplot(2,1,1); h1 = plot(ax1, NaN, NaN, 'b', NaN, NaN, 'g'); grid(ax1,'on');
ylabel(ax1,'T [\circC]'); legend(ax1,'Chamber','Ambient');
ax2 = subplot(2,1,2); h2 = stairs(ax2, NaN, NaN, 'r'); grid(ax2,'on');
ylabel(ax2,'u [V]'); xlabel(ax2,'t [s]');

t0 = tic; k = 0;
while true
    k = k + 1; tk = (k-1)*Ts;
    if tk > TT || ~isvalid(fig), break; end
    while toc(t0) < tk, pause(0.002); end
    try
        m = hw_read(dIn, HW);
    catch ME
        write(dOut, 0); warning(ME.message); break;
    end
    u = 0; if tk >= T_PRE && tk < T_PRE + T_ON, u = U_STEP; end
    safety = (m.Tc > T_ABS_MAX) || (m.Tc > m.Ta + DT_MAX);
    if safety, u = 0; end
    write(dOut, u);
    rec(k,:) = [tk u m.Tc m.Ta m.I m.Vh safety];
    if mod(k, 4) == 0
        set(h1(1),'XData',rec(1:k,1),'YData',rec(1:k,3));
        set(h1(2),'XData',rec(1:k,1),'YData',rec(1:k,4));
        set(h2,'XData',rec(1:k,1),'YData',rec(1:k,2));
        title(ax1, sprintf('t = %.0f / %.0f s   Tc = %.2f C', tk, TT, m.Tc));
        drawnow limitrate;
    end
end
write(dOut, 0);
rec = rec(~isnan(rec(:,1)), :);
S = struct('t',rec(:,1),'u',rec(:,2),'Tc',rec(:,3),'Ta',rec(:,4), ...
           'I',rec(:,5),'Vh',rec(:,6),'safety',rec(:,7),'U_STEP',U_STEP,'T_PRE',T_PRE,'T_ON',T_ON,'Ts',Ts);
fn = fullfile('results', ['step_' datestr(now,'yyyymmdd_HHMM')]);
save([fn '.mat'], '-struct', 'S');
writetable(struct2table(rmfield(S,{'U_STEP','T_PRE','T_ON','Ts'})), [fn '.csv']);
saveas(fig, [fn '.png']);
fprintf('Saved %s.mat  ->  now run identify_model.m\n', fn);
