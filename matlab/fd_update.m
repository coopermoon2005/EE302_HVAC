function [st, flag, label] = fd_update(st, t, Tm, That, u, I_heat, FD, Ts)
%FD_UPDATE  One step of the model-based fault detector (same code for sim + hardware)
%   st     : state struct; start with st = fd_update()  (no inputs) to initialise
%   t      : time [s]           Tm   : measured chamber temp [degC]
%   That   : nominal-model prediction [degC]   u : heater command [V]
%   I_heat : measured heater current [A] (NaN if not available)
%   Returns flag (true = fault) and a label string.
%
% Logic:
%   r   = Tm - That                (model residual)
%   r_f = low-pass(r, FD.Tf)
%   FAULT if |r_f| > FD.R_TH continuously for FD.T_HOLD s (after FD.T_ARM s)
%   HEATER fault if u > 0.5 V but current < FD.I_MIN for FD.T_HOLD s
%   Classification:
%     sudden jump in Tm (> FD.JUMP_TH per sample) shortly before -> SENSOR BIAS
%     r_f > 0 (hotter than model)  -> LOW AIRFLOW (fan failure / restriction)
%     r_f < 0 (colder than model)  -> EXCESS COOLING / WEAK HEATER
if nargin == 0
    st = struct('rf',0,'t_over',0,'t_heat',0,'Tm_prev',NaN,'jump_t',-Inf, ...
                'r',0,'label','OK');
    return;
end
alpha = 1 - exp(-Ts / FD.Tf);
st.r  = Tm - That;
st.rf = st.rf + alpha * (st.r - st.rf);

if ~isnan(st.Tm_prev) && abs(Tm - st.Tm_prev) > FD.JUMP_TH
    st.jump_t = t;
end
st.Tm_prev = Tm;

flag = false; label = 'OK';
if t < FD.T_ARM
    st.label = label; return;
end

if abs(st.rf) > FD.R_TH, st.t_over = st.t_over + Ts; else, st.t_over = 0; end
if ~isnan(I_heat) && u > 0.5 && I_heat < FD.I_MIN
    st.t_heat = st.t_heat + Ts;
else
    st.t_heat = 0;
end

if st.t_heat >= FD.T_HOLD
    flag = true; label = 'HEATER FAULT (no current)';
elseif st.t_over >= FD.T_HOLD
    flag = true;
    if t - st.jump_t < 90
        label = 'SENSOR BIAS / SENSOR FAULT';
    elseif st.rf > 0
        label = 'LOW AIRFLOW (fan failure / restriction)';
    else
        label = 'EXCESS COOLING / WEAK HEATER';
    end
end
st.label = label;
end
