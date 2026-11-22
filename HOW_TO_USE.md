# How to Use This Folder

## 1. Hardware setup

1. Plug the **QNET HVAC Trainer** board into the **NI ELVIS II+** slot.
2. Connect the ELVIS to the PC with the **USB cable**.
3. Plug the **QNET power adapter** into the QNET board's power jack and switch it on.
4. Switch on the **ELVIS** (power switch at the back) and the **Prototyping Board Power** switch.
5. Check the LEDs on the QNET board: **+15 V, −15 V and +B** must all be lit. The fan should be spinning.
6. Keep the **3D-printed airflow plates** (`hardware/stl/`) next to the fan end:
   - **50 % plate**: restricted airflow / disturbance
   - **0 % (closed) plate**: fan failure
   - Plates go on the **fan end only**, never near the lamp.
7. Close **NI MAX**, the **ELVISmx Instrument Launcher** and **LabVIEW** before running MATLAB. They lock the device.

**Software needed:** MATLAB with Simulink and the Data Acquisition Toolbox, the *Data Acquisition Toolbox Support Package for NI-DAQmx Devices*, and NI-DAQmx with NI-ELVISmx installed as the same version (e.g. both 2025 Q4).

---

## 2. Folder contents

```
EE302_HVAC/
  matlab/        all MATLAB code (make this the current folder)
    results/     logged runs, figures and tables
  hardware/      3D-printable airflow plates (OpenSCAD + STL) and photos
  docs/          report, slides, figures, viva notes
```

---

## 3. What each file does

### Run these

| File | Task | Hardware? | Time |
|---|---|---|---|
| `hw_check_io.m` | Finds the ELVIS, prints sensor readings, optional 30 s heater test | Yes | 1 min |
| `hw_step_test.m` | Open-loop step test (heater 3 V) for system identification | Yes | 10 min |
| `identify_model.m` | Fits K, τ, L to the step test, saves `hvac_identified.mat` | No | seconds |
| `build_hvac_model.m` | Builds the Simulink model `HVAC_Sim.slx` | No | seconds |
| `run_simulations.m` | Runs all 8 simulated scenarios, saves figures and tables | No | < 1 min |
| `hw_run_control.m` | Real-time ON-OFF or PI control with fault detection and live plot | Yes | up to 20 min |
| `run_unattended.m` | Queues several hardware runs that need no plate changes | Yes | long |
| `analyze_results.m` | Replays each hardware run in Simulink, writes comparison tables | No | 1–2 min |

### Helper files (called automatically, not run directly)

| File | Task |
|---|---|
| `hvac_params.m` | All settings: channels, safety limits, model, PI gains, detector thresholds |
| `hw_open.m` | Opens the ELVIS channels |
| `hw_read.m` | Reads and scales all sensors |
| `fd_update.m` | Fault detector (used by hardware runs and simulations) |
| `step_metrics.m` | Rise time, settling time, overshoot, steady-state error, ripple |
| `tools/` | Hardware diagnostics (`list_daq_devices.m`, `heater_check.m`) |

---

## 4. How to run

Open MATLAB and go to the code folder first:

```matlab
cd('<path to>\EE302_HVAC\matlab')
```

### Full sequence (first time)

```matlab
hw_check_io          % 1. check hardware
hw_step_test         % 2. step test (start with the chamber at room temperature)
identify_model       % 3. fit the model
build_hvac_model     % 4. build the Simulink model
run_simulations      % 5. simulations
hw_run_control       % 6. hardware runs (repeat for each controller and scenario)
analyze_results      % 7. hardware vs. simulation tables
```

### Hardware run settings

Either edit the top of `hw_run_control.m` (`CTRL`, `SCENARIO`) or set them from the command line:

```matlab
setenv('HVAC_CTRL','2'); setenv('HVAC_SCENARIO','dist'); hw_run_control
```

| `CTRL` | Controller |
|---|---|
| 1 | ON-OFF |
| 2 | PI |

| `SCENARIO` | What to do during the run |
|---|---|
| `track` | Nothing (setpoint steps +4, +6, +3 °C) |
| `normal` | Nothing (fault-free baseline) |
| `dist` | ~400 s: 50 % plate on, press `d`; ~800 s: remove, press `d` |
| `restrict` | ~400 s: 50 % plate on, press `f`, leave it |
| `fanfail` | ~400 s: 0 % plate on, press `f`, leave it |
| `bias` | Nothing (+2 °C sensor bias switches on at 400 s, or press `b`) |

**Keys** (click the plot window first): `d` disturbance plate in/out, `f` fault plate in/out, `b` sensor bias on/off, `q` stop. The heater turns off on `q` and when the script ends.

**Before every hardware run:** let the chamber cool (heater off, fan on) until its temperature stops falling.

### Short live demo (about 3 minutes)

```matlab
cd('<path to>\EE302_HVAC\matlab'); hvac_params; open_system('HVAC_Sim'); setenv('HVAC_CTRL','2'); setenv('HVAC_SCENARIO','dist'); hw_run_control
```

1. Wait until the temperature settles and at least 60 s have passed.
2. Put the 50 % plate on the fan and press `d`. Expect **LOW AIRFLOW** after about 30 s.
3. Remove the plate and press `d`, then press `b`. Expect **SENSOR BIAS** after about 20–35 s.
4. Press `q`.

After the demo, move the demo files out of the main results so they don't replace the original runs:

```matlab
setenv('HVAC_CTRL',''); setenv('HVAC_SCENARIO','');
movefile(fullfile('results',['hw_*_' datestr(now,'yyyymmdd') '_*']), fullfile('results','archive'))
```

---

## 5. Results you get

All outputs go to `matlab/results/`.

| Produced by | Files | Content |
|---|---|---|
| `hw_step_test` | `step_<date>.mat/.csv/.png` | Step-test data |
| `identify_model` | `hvac_identified.mat`, `fig_identification.png` | K, τ, L and the fit plot |
| `run_simulations` | `sim_*.mat`, `fig_sim_tracking.png`, `fig_sim_disturbance.png`, `fig_sim_faults.png`, `sim_metrics.csv`, `sim_faults.csv` | Simulated responses, metrics and fault detection |
| `hw_run_control` | `hw_<ctrl>_<scenario>_<date>.mat/.csv/.png` | One logged hardware run: setpoint, temperature, heater command, current, voltage, model prediction, residual, alarms |
| `analyze_results` | `fig_hw_*.png`, `hw_metrics.csv`, `hw_faults_energy.csv` | Hardware vs. simulation plots, tracking metrics, detection delays, energy |

**Live plot during `hw_run_control`:**
- Top: setpoint, measured temperature, model prediction
- Middle: heater command (0–5 V)
- Bottom: filtered residual (alarm when above ±1.3 °C for 15 s)
- Title: time, temperature, detector status

**Detector messages:** `LOW AIRFLOW`, `SENSOR BIAS / SENSOR FAULT`, `EXCESS COOLING / WEAK HEATER`, `HEATER FAULT (no current)`.

**Documentation:** report `docs/report/report.pdf`, slides `docs/slides/slides.pdf`. To rebuild the print figures: `python docs/make_figures.py`.
