% heater_check.m -- QNET HVAC on ELVIS II+ (heater drive = ao1, found by scan)
clear; clc;
dev = "Dev1"; cmd = 5; fs = 5; maxT = 60;

di = daq("ni");
for k = 0:7
    c = addinput(di, dev, "ai"+k, "Voltage"); c.TerminalConfig = "Differential";
end
do = daq("ni"); addoutput(do, dev, "ao1", "Voltage");
cl = onCleanup(@() write(do, 0));
write(do, 0); pause(15);                 % let inputs settle

D = []; tic
while toc < 10, D(end+1,:) = rowRead(di); pause(1/fs); end
v0 = mean(D(end-9:end,:));               % baseline, columns = ai0..ai7

write(do, cmd); E = []; tic
while toc < maxT
    E(end+1,:) = [toc rowRead(di)];
    if any(E(end,[7 8]) - v0([6 7]) > 1), disp("Over-temp abort"), break, end
    pause(1/fs);
end
write(do, 0);

dv  = E(:,2:end) - v0;                   % change vs baseline
n   = min(10, size(dv,1));
fin = mean(dv(end-n+1:end,:));
elec  = max(abs(fin([4 5]))) > 1;        % ai3/ai4 step: drive reaches heater
therm = max(fin([6 7])) > 0.1;           % ai5/ai6 rising: chamber heating

fprintf("ai3/ai4 step: %.2f / %.2f V\n", fin(4), fin(5));
fprintf("ai5/ai6 rise: %.3f / %.3f V over %.0f s\n", fin(6), fin(7), E(end,1));
if elec && therm
    disp("PASS: heater is working")
elseif elec
    disp("PARTIAL: drive reaches heater, temp not rising yet (run longer / check sensors)")
else
    disp("FAIL: no response -> check board power (+B LED), fuse, connections")
end

figure
subplot(2,1,1); plot(E(:,1), dv(:,[4 5])); grid on; ylabel("ai3, ai4 [V]")
subplot(2,1,2); plot(E(:,1), dv(:,[6 7])); grid on; ylabel("ai5, ai6 [V]"); xlabel("s")

function r = rowRead(d)
s = read(d); r = s{1,:};
end