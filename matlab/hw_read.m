function m = hw_read(dIn, HW)
%HW_READ  On-demand read of all inputs, averaged over HW.n_avg scans, scaled to units.
%   m.Tc [degC], m.Ta [degC], m.I [A], m.Vh [V], m.raw [V x4]
v = zeros(HW.n_avg, 4);
for k = 1:HW.n_avg
    v(k,:) = read(dIn, "OutputFormat", "Matrix");
end
v = mean(v, 1);
m.raw = v;
m.Tc  = HW.k_T * v(1) + HW.Tc_off;
m.Ta  = HW.k_T * v(2);
m.I   = HW.k_I * v(3);
m.Vh  = HW.k_V * v(4);
end
