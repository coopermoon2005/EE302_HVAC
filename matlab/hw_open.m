function [dIn, dOut, HW] = hw_open(HW)
%HW_OPEN  Open NI ELVIS II+ through Data Acquisition Toolbox (NI-DAQmx).
%   Input order in every read: [chamber Tc, ambient Ta, heater I, heater V]
%   Close NI ELVISmx Instrument Launcher, NI MAX test panels and any LabVIEW
%   QNET VI first -- they reserve the device.
if ~exist('daq', 'file')
    error(['Data Acquisition Toolbox not found. Install it + "Data Acquisition ' ...
           'Toolbox Support Package for National Instruments NI-DAQmx Devices".']);
end
if isempty(HW.device)
    dl = daqlist("ni");
    if isempty(dl), error('No NI devices found. Is ELVIS on, USB in, NI-DAQmx installed? Check NI MAX.'); end
    disp(dl(:, {'DeviceID','Model'}));
    hit = find(contains(string(dl.Model), "ELVIS", 'IgnoreCase', true), 1);
    if isempty(hit), error('No ELVIS in the list above. Set HW.device manually in hvac_params.m'); end
    HW.device = char(dl.DeviceID(hit));
end
fprintf('Using device %s\n', HW.device);

dIn = daq("ni");
chans = {HW.ch_Tc, HW.ch_Ta, HW.ch_Ic, HW.ch_Vh};
for k = 1:numel(chans)
    ch = addinput(dIn, HW.device, chans{k}, "Voltage");
    ch.TerminalConfig = HW.term_cfg;
    ch.Range = [-10 10];
end
dOut = daq("ni");
addoutput(dOut, HW.device, HW.ch_heat, "Voltage");
write(dOut, 0);                       % heater OFF immediately
end
