# BayIW_Rectan_2layer — Internal Waves in a Rectangular Bay (Two-Layer Stratification)

**Master's Degree Thesis Project**

This project uses the [MITgcm](https://mitgcm.org/) ocean general circulation model to simulate the generation and propagation of **internal waves** in a rectangular bay using an **idealized two-layer stratification**. It is one of three stratification cases studied in the thesis:

| Case | Repository | Stratification |
|---|---|---|
| Realistic | `BayIW_Rectan/` | February climatological T/S profiles |
| **Two-layer** | **`BayIW_Rectan_2layer/`** | Idealized two-layer temperature profile, no salinity |
| Linear | `BayIW_Rectan_linear/` | Linearly varying density profile |

The simulations are run with and without the bay geometry to isolate the bay's influence on internal wave dynamics.

---

## Project Structure

```
BayIW_Rectan_2layer/
├── build/                        # MITgcm compilation directory
├── code/                         # Model configuration and size files
│   ├── SIZE.h                    # Grid decomposition parameters
│   ├── packages.conf             # Enabled MITgcm packages
│   ├── OBCS_OPTIONS.h            # Open boundary condition options
│   └── DIAGNOSTICS_SIZE.h        # Diagnostics buffer sizes
├── input/                        # Forcing, bathymetry, and preprocessing scripts
│   ├── *.bin                     # Binary input files (bathymetry, grid spacing, wind)
│   ├── profiles_2layer/          # Two-layer T/S profile binary files
│   │   ├── T_2layer_50z_560x352.bin
│   │   └── S_dummy_50z_560x352.bin
│   ├── STATE/                    # Reference state generation scripts
│   ├── *.ipynb                   # Jupyter notebooks for input generation
│   └── *.py                      # Python utility scripts
├── run_expand/                   # Run directory — with bay geometry
│   ├── data                      # Main model parameter file
│   ├── data.diagnostics          # Diagnostics configuration
│   ├── data.obcs                 # Open boundary condition parameters
│   ├── data.pkg                  # Package switches
│   ├── data.mnc                  # NetCDF output settings
│   └── mnc_*/                    # NetCDF output directories (one per MPI rank)
├── run_expand_nobay/             # Run directory — without bay (control case)
├── compile_and_run_expand.sh     # Script to compile and run both simulations
└── run_expands.sh                # Run-only script (no recompilation)
```

---

## Model Configuration

| Parameter | Value |
|---|---|
| Model | MITgcm |
| Grid type | Cartesian |
| Horizontal resolution | Variable (expanded grid: 560 × 352 points) |
| Vertical levels | 50 (stretched: 1 m near surface to ~46 m at depth) |
| Time step | 30 s |
| Simulation duration | 432 000 s total (~5 days, two stages) |
| Equation of state | Linear (temperature only, no salinity effect) |
| Free surface | Implicit |
| Lateral viscosity | 100 m² s⁻¹ |
| Vertical viscosity | 1 × 10⁻⁵ m² s⁻¹ |
| Coriolis parameter (f₀) | 6.97 × 10⁻⁵ s⁻¹ |

### Packages used

| Package | Purpose |
|---|---|
| OBCS | Open boundary conditions (Orlanski radiation + sponge layers) |
| Diagnostics | Output of density anomaly fields (`RHOAnoma`) |
| MNC | NetCDF output |

### Boundary conditions

Open boundaries are applied on the south, west, and east edges using **Orlanski radiation** conditions. A sponge layer of 10 grid cells damps spurious reflections near the boundaries. Barotropic velocity balance is applied to maintain mass conservation.

### Forcing

- **Wind**: Periodic meridional wind forcing applied in stage 1 only (period = 1200 s, cycle = 216 000 s)
- **Initial temperature**: Idealized two-layer profile (`T_2layer_50z_560x352.bin`), with a uniform reference temperature of 11.4°C
- **Salinity**: Not active — zero salinity, no haline contraction (β = 0). Density is driven purely by temperature.

### Two-layer stratification

The stratification is defined by a step-like temperature profile that divides the water column into two layers separated by a sharp thermocline. Salinity is set to zero throughout, so all density variation comes from temperature alone. This is the simplest idealization that supports internal wave propagation along the density interface.

---

## Simulation Cases

| Run directory | Bay geometry | Description |
|---|---|---|
| `run_expand/` | With bay | Primary case with rectangular bay bathymetry |
| `run_expand_nobay/` | Without bay | Control case — open coastal domain |

Both cases share the same model executable and physical parameters, and follow the same two-stage run strategy described below.

### Two-stage run strategy

Each simulation is run in two consecutive stages:

| Stage | `startTime` | `endTime` | `nIter0` | Wind forcing | Purpose |
|---|---|---|---|---|---|
| 1 — Forced | 0 s | 216 000 s (~2.5 days) | 0 | ON (periodic, 1200 s period) | Wind-driven internal wave generation |
| 2 — Free | 216 000 s | 432 000 s (~5 days total) | 7200 | OFF | Free propagation and decay after forcing stops |

Stage 1 starts from rest with the two-layer T/S initial conditions and applies periodic wind forcing. It writes a checkpoint (`ckptA`) at the end. Stage 2 restarts from that checkpoint (`pickupSuff='ckptA'`) with the wind forcing disabled, allowing the internal wave field to propagate and decay freely.

The `data` files committed to the repository correspond to **stage 2**. To run stage 1, update `&PARM03` to:
```
startTime=0., endTime=216000., nIter0=0,
periodicExternalForcing=.TRUE., externForcingPeriod=1200., externForcingCycle=216000.,
```
and uncomment the `meridWindFile` and `hydrogThetaFile` lines in `&PARM05`.

---

## Differences from the Realistic Stratification Case

| Parameter | Realistic (`BayIW_Rectan`) | Two-layer (`BayIW_Rectan_2layer`) |
|---|---|---|
| Temperature profile | February climatology (varies with depth) | Idealized two-layer step profile |
| Salinity profile | February climatology (33.6 → 34.7 PSU) | Zero (no salinity effect) |
| Haline contraction β | 7.4 × 10⁻⁴ PSU⁻¹ | 0 (disabled) |
| Reference T (tRef) | 16.58°C (uniform) | 11.4°C (uniform) |
| Reference S (sRef) | 33.6 PSU | 0.0 PSU |
| Salt time-stepping | Enabled | Disabled |
| Run strategy | Two stages: forced (0–216 000 s) then free (216 000–432 000 s) | Same two-stage strategy |
| T/S input files | `feb_temp/salt_50zlev_560x352.bin` | `T_2layer_50z_560x352.bin`, `S_dummy_50z_560x352.bin` |

---

## Input File Generation

The `input/` directory contains Jupyter notebooks used to prepare all binary input files:

| Notebook | Purpose |
|---|---|
| `bahia_01_expand*.ipynb` | Bay bathymetry generation and refinement |
| `make_binary_*.ipynb` | Convert bathymetry to MITgcm binary format |
| `make_T_S_bin_2Layer.ipynb` | Generate two-layer T/S initial conditions |
| `make_T_S_binary_files_linear.ipynb` | Generate linear stratification T/S (for reference) |
| `make_wind_forcing*.ipynb` | Generate wind forcing fields |
| `check_output*.ipynb` | Post-processing and visualization of model output |
| `compute_wind_energy.ipynb` | Compute wind energy input to the ocean |

---

## How to Compile and Run

### Requirements

- MITgcm source tree (expected at `../../../` relative to this directory)
- Fortran compiler (`gfortran`) — build options configured for `darwin_arm64_gfortran`
- MPI (optional, for parallel runs)
- Python 3 with `numpy`, `netCDF4`, `matplotlib` (for preprocessing and analysis)

### Compilation and execution

```bash
bash compile_and_run_expand.sh
```

The script will interactively ask whether to:
1. Clean the `build/` directory before compiling
2. Enable MPI compilation
3. Clean run directories before execution
4. Run with MPI (and how many cores)

Both `run_expand/` (with bay) and `run_expand_nobay/` (without bay) are run sequentially by the script.

### Run only (no recompilation)

```bash
bash run_expands.sh
```

### Manual run (single case)

```bash
cd run_expand
cp ../build/mitgcmuv .
./mitgcmuv > output.txt
```

Or with MPI (4 cores):

```bash
mpirun -np 4 ./mitgcmuv > output.txt
```

---

## Output

Model output is written as **NetCDF** files into `mnc_*/` subdirectories (one per MPI rank) within each run directory. The primary diagnostic field is:

- `diag_rho` — density anomaly (`RHOAnoma`), output every 900 s (15 min)

---

## Scientific Context

Internal waves are gravity waves that propagate along density interfaces in the ocean interior. In the idealized two-layer configuration, the single sharp density interface between the upper and lower layers acts as a waveguide, producing a clean internal wave signal that is easier to analyze than in the realistic or linear stratification cases. This allows direct comparison of:

1. Internal wave phase speeds and wavelengths predicted by two-layer theory vs. simulated results
2. The role of the bay in trapping and modifying the wave field
3. How the choice of stratification profile affects wave amplitude and energy distribution

---

## Author

Master's Degree Thesis — *[University name]*
