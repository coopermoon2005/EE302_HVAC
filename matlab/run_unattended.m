function run_unattended(runs)
%RUN_UNATTENDED  Hardware runs that need nobody at the rig (no plate changes).
%   run_unattended            -> PI 'normal' then PI 'bias' (bias switches on by itself)
%   run_unattended(runs)      -> runs = {'1','track'; '2','track'} etc. ({CTRL, SCENARIO})
% Waits for the chamber to stop cooling before each run.
% Start from a shell:  matlab -batch "run_unattended"
if nargin < 1, runs = {'2','normal'; '2','bias'}; end
for k = 1:size(runs,1)
    cooldown(15*60, 1.0);
    fprintf('\n===== %s  starting run: CTRL=%s SCENARIO=%s =====\n', datestr(now), runs{k,:});
    one_run(runs{k,1}, runs{k,2});
end
fprintf('\n===== %s  all unattended runs finished =====\n', datestr(now));
end

function one_run(ctrl, scen)
% Own workspace, so the "clear" inside hw_run_control cannot wipe the loop above.
% (No onCleanup here: the script's "clear" would fire it before the settings are read.)
setenv('HVAC_CTRL', ctrl); setenv('HVAC_SCENARIO', scen);
hw_run_control;
setenv('HVAC_CTRL', ''); setenv('HVAC_SCENARIO', '');
end

function cooldown(t_max, ~)
% Heater off; wait until the chamber has stopped cooling (it is the detector's
% resting reference): drop over the last 120 s below 0.1 degC, or T_MAX seconds.
hvac_params;
[dIn, dOut, ~] = hw_open(HW); write(dOut, 0);
t0 = tic; t_print = -Inf; hist = [];
while true
    m = hw_read(dIn, HW); dT = m.Tc - m.Ta;
    hist(end+1,:) = [toc(t0) m.Tc]; %#ok<AGROW>
    old = hist(hist(:,1) <= toc(t0) - 120, 2);
    if toc(t0) > 180 && ~isempty(old) && mean(old(max(end-9,1):end)) - mean(hist(max(end-9,1):end,2)) < 0.1, break; end
    if toc(t0) > t_max, break; end
    if toc(t0) - t_print >= 60
        fprintf('cooling: chamber %.2f C, ambient %.2f C\n', m.Tc, m.Ta); t_print = toc(t0);
    end
    pause(1);
end
fprintf('Cooldown done after %.0f s (chamber - ambient = %.2f C)\n', toc(t0), dT);
end
