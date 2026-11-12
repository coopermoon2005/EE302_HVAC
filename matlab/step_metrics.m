function m = step_metrics(t, y, r0, r1, t0, t1, band)
%STEP_METRICS  Rise time, settling time, overshoot, steady-state error, ripple
%   m = step_metrics(t, y, r0, r1, t0, t1, band)
%   t,y   : time [s] and measured temperature [degC]
%   r0,r1 : setpoint before / after the step [degC]
%   t0,t1 : step time and end of the analysis window [s]
%   band  : settling band [degC] (absolute, e.g. 0.5)
%   Rise time = 10%->90%. Settling = last entry into +/-band. ess = mean error in
%   final 20% of window. Ripple = peak-to-peak in final 20% (ON-OFF limit cycle).
t = t(:); y = y(:);
idx = t >= t0 & t < t1;
tt = t(idx) - t0;  yy = y(idx);
dy = r1 - r0;
m = struct('rise_s',NaN,'settle_s',NaN,'overshoot_pct',NaN,'ess_degC',NaN,'ripple_degC',NaN);
if numel(tt) < 5 || abs(dy) < 1e-6, return; end

yn  = (yy - r0) / dy;
i10 = find(yn >= 0.1, 1);  i90 = find(yn >= 0.9, 1);
if ~isempty(i10) && ~isempty(i90), m.rise_s = tt(i90) - tt(i10); end

m.overshoot_pct = max(0, max((yy - r1) * sign(dy))) / abs(dy) * 100;

out = find(abs(yy - r1) > band, 1, 'last');
if isempty(out)
    m.settle_s = 0;
elseif out < numel(tt)
    m.settle_s = tt(out + 1);
end                                    % else NaN = never settled in window

tail = tt >= 0.8 * tt(end);
m.ess_degC    = r1 - mean(yy(tail));
m.ripple_degC = max(yy(tail)) - min(yy(tail));
end
