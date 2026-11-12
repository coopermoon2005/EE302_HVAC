# HVAC Temperature Control and Fault Detection

Closed-loop temperature control and model-based fault detection for the Quanser
QNET HVAC Trainer (QNET-HVACT) on an NI ELVIS II+, written in MATLAB/Simulink.

- **System identification**: open-loop step test → first-order-plus-dead-time model
- **Control**: ON-OFF with hysteresis vs. PI (SIMC tuning, clamping anti-windup), 2 Hz real-time loop
- **Fault detection**: residual between the measured temperature and a nominal model running in parallel,
  low-pass filtered and thresholded; faults are classified as low airflow, excess cooling / weak heater,
  sensor bias, or heater failure
- **Validation**: every experiment is replayed in Simulink with the same inputs, and hardware and
  simulation are compared side by side

Documentation: [report](docs/report/report.pdf) · [slides](docs/slides/slides.pdf)

Somanshu Juneja (B24354), Ridhi Garg (B24348), Pramukto Mandal (B24347) ·
EE302 Control Systems Laboratory, IIT Mandi · Group 2, Problem Statement 4

## Results at a glance

| Experiment (PI unless noted) | Fault applied at | Detected after | Classified as |
|---|---|---|---|
| Fault-free, constant setpoint | – | no alarm | – |
| Airflow restricted (50 % plate) | 416.5 s | 32.0 s | low airflow |
| Fan blocked (0 % plate) | 422.5 s | 38.5 s | low airflow |
| Sensor bias +2 °C | 400.0 s | 21.5 s | sensor bias |
| Disturbance, ON-OFF | 404.5 s | 32.0 s | low airflow |
| Disturbance, PI | 406.5 s | 30.0 s | low airflow |

The PI loop settles setpoint steps in 13.5–29 s and holds the chamber within about 0.35 °C of the
setpoint through every airflow fault, while the ON-OFF loop keeps a limit cycle of about 0.8 °C
peak-to-peak and, for the same mean heater command, uses about twice the electrical energy.

## Repository layout

```
matlab/                 everything that runs in MATLAB (make this the current folder)
  hvac_params.m         every number: channels, scalings, safety limits, model, gains, faults
  hw_*.m                hardware I/O, step test, real-time control loop
  identify_model.m      fits K, tau, L to the step test -> hvac_identified.mat
  build_hvac_model.m    generates the Simulink model HVAC_Sim.slx
  run_simulations.m     all simulated scenarios
  run_unattended.m      hardware runs that need no manual plate changes
  analyze_results.m     hardware vs. simulation, metrics, fault and energy tables
  fd_update.m           fault detector (identical code in simulation and on hardware)
  step_metrics.m        rise / settling time, overshoot, steady-state error, ripple
  results/              logged runs (.mat/.csv/.png) and generated tables
    archive/            superseded runs kept for reference
  tools/                one-off hardware diagnostics
hardware/               3D-printable airflow plates for the fan (OpenSCAD source + STL)
  photos/               fan end without a plate and with the 0 % plate fitted
docs/
  make_figures.py       rebuilds the print figures from matlab/results
  figures/              figures used in the report and slides
  report/               report source (LaTeX) and PDF
  slides/               slide source (LaTeX beamer) and PDF
```

## Requirements

- MATLAB with Simulink and the Data Acquisition Toolbox
- *Data Acquisition Toolbox Support Package for National Instruments NI-DAQmx Devices*
- NI-DAQmx and NI ELVISmx drivers (Windows)
- For the documentation only: Python 3 with NumPy, SciPy, Matplotlib; a LaTeX distribution

## Running it

Make `matlab/` the current folder in MATLAB, then:

1. `hw_check_io` – finds the ELVIS, checks the channels, short heater test
2. `hw_step_test` – 10 min open-loop step (start with the chamber at room temperature)
3. `identify_model` – fits the model and saves `hvac_identified.mat`
4. `build_hvac_model` – creates `HVAC_Sim.slx`
5. `run_simulations` – simulated scenarios, plots and tables in `results/`
6. `hw_run_control` – one real-time run; set `CTRL` (1 = ON-OFF, 2 = PI) and `SCENARIO` at the top

   | Scenario | What to do during the run |
   |---|---|
   | `track` | nothing (setpoint staircase) |
   | `normal` | nothing (fault-free baseline) |
   | `dist` | ~400 s: 50 % plate on the fan, press `d`; ~800 s: remove it, press `d` |
   | `restrict` | ~400 s: 50 % plate on the fan, press `f`; leave it on |
   | `fanfail` | ~400 s: 0 % plate on the fan, press `f`; leave it on |
   | `bias` | nothing: a +2 °C sensor bias switches on at 400 s (or press `b`) |

   Click the plot window before pressing a key; `q` stops the run. Runs that need no plate
   change can be queued with `run_unattended({'2','normal'; '2','bias'})`.
7. `analyze_results` – uses the newest run of each kind and writes the comparison tables

Let the chamber cool between runs (heater off, fan on) until its temperature stops falling;
the detector takes that resting value as its reference.

To rebuild the documentation figures: `python docs/make_figures.py`.

## Safety

The heater command is capped at 5 V. The heater is forced off above 45 °C or 20 °C above
ambient, on any read error, on `q`, and when a script exits. The airflow plates go on the
fan end only, never on the lamp end.

## Notes

- The heater current and voltage scalings (`HW.k_I`, `HW.k_V`) are provisional, so the energy
  figures in joules are approximate; actuator effort (V·s) and duty cycle do not depend on them.
- The detector's nominal model uses `K = 1.41 °C/V, τ = 19.6 s`, refitted on closed-loop data;
  the PI gains are still the ones tuned from the step-test model (`K = 1.71 °C/V, τ = 33.7 s`).
  The step-test fit is kept in `matlab/results/archive/hvac_identified_steptest.mat`.
