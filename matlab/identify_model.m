%% identify_model.m  --  fit K, tau, L of  tau*dT/dt = K*u(t-L) - (T-Ta)  to step data
% Uses the newest results/step_*.mat (or pick one). Saves hvac_identified.mat,
% which hvac_params.m loads automatically from then on.
clear; clc; close all;
hvac_params;
f = dir(fullfile('results','step_*.mat'));
if isempty(f), error('No results/step_*.mat. Run hw_step_test.m first.'); end
[~, i] = max([f.datenum]);
S = load(fullfile(f(i).folder, f(i).name));
fprintf('Identifying from %s\n', f(i).name);

t = S.t; u = S.u; Ts_d = S.Ts;
Ta0 = mean(S.Ta(t < S.T_PRE));              % latched ambient (baseline)
y   = S.Tc - Ta0;                           % rise above ambient
y   = y - mean(y(t < S.T_PRE));             % remove small sensor offset at baseline

simf = @(p) sim_fo(p, u, Ts_d, y(1));
cost = @(p) sum((simf(abs(p)) - y).^2);
p0 = [y(find(t < S.T_PRE + S.T_ON, 1, 'last')) / S.U_STEP, 20, 2];   % initial guess
opts = optimset('Display','off','MaxFunEvals',4000,'MaxIter',4000);
p = abs(fminsearch(cost, p0, opts));
K = p(1); tau = p(2); L = p(3);
yh = simf(p);
fit = 100 * (1 - norm(y - yh) / norm(y - mean(y)));

fprintf('\n  K   = %.3f degC/V\n  tau = %.1f s\n  L   = %.1f s\n  fit = %.1f %%  (NRMSE)\n', K, tau, L, fit);
fprintf('  Max reachable rise at U_MAX=%.1f V: %.1f degC  (keep setpoints below this - 1)\n', ...
        U_MAX, K*U_MAX);
save('hvac_identified.mat', 'K', 'tau', 'L', 'fit', 'Ta0');

fig = figure('Name','Model identification');
subplot(2,1,1); plot(t, y + Ta0, 'b', t, yh + Ta0, 'r--', 'LineWidth', 1.2); grid on;
legend('Measured','Model'); ylabel('T [\circC]');
title(sprintf('K = %.2f \\circC/V,  \\tau = %.0f s,  L = %.1f s,  fit = %.1f%%', K, tau, L, fit));
subplot(2,1,2); stairs(t, u, 'k'); grid on; ylabel('u [V]'); xlabel('t [s]');
saveas(fig, fullfile('results','fig_identification.png'));
disp('Saved hvac_identified.mat. Re-run run_simulations.m to use the fitted model.');

function yh = sim_fo(p, u, Ts, y0)
% Euler simulation of tau*dy/dt = K*u(t-L) - y, sampled at Ts
K = p(1); tau = max(p(2), Ts); d = round(p(3) / Ts);
n = numel(u); yh = zeros(n,1); yh(1) = y0;
for k = 1:n-1
    j = max(k - d, 1);
    yh(k+1) = yh(k) + Ts / tau * (K * u(j) - yh(k));
end
end
