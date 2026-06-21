#!/bin/bash
#==============================================================================
# submit_2stage_2layer.slurm
# Corrida completa en 2 etapas del caso DOS CAPAS
#   - run_expand        (con bahia)
#   - run_expand_nobay  (control sin bahia)
#
# Etapa 1 (forzada):  startTime=0      -> endTime=216000 s, nIter0=0
#                     viento periodico ON, lee T (y S) propios del caso,
#                     escribe el checkpoint permanente pickup.0000007200
# Etapa 2 (libre):    startTime=216000 -> endTime=432000 s, nIter0=7200
#                     reinicia desde pickup.0000007200, viento OFF
#
# Requiere build/mitgcmuv ya compilado (MPI, SIZE.h 5x4 = 20 ranks) con el
# optfile AVX2 (nodos Haswell, sin AVX-512). Compilacion previa:
#   source /LUSTRE/HOME/esteban/MITgcm/setup_env.sh
#   cd build && ../../../tools/genmake2 -mods=../code -mpi -of=../optfile_ometeotl_avx2
#   make depend && make -j 8
#
# Envio:  sbatch submit_2stage_2layer.slurm
#==============================================================================
#SBATCH --job-name=BayIW_2layer
#SBATCH --partition=id
#SBATCH --nodes=1
#SBATCH --ntasks=20                # = nPx*nPy de SIZE.h (5x4)
#SBATCH --cpus-per-task=1
#SBATCH --time=2-00:00:00
#SBATCH --output=/LUSTRE/HOME/esteban/MITgcm/verification/BayIW_Rectan_2layer/logs/%x_%j.log
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=estebanci@atmosfera.unam.mx

set -eo pipefail   # sin '-u': los scripts de entorno de Intel usan vars sin asignar

EXP=/LUSTRE/HOME/esteban/MITgcm/verification/BayIW_Rectan_2layer
NP=${SLURM_NTASKS:-20}

# --- Entorno Intel (ifort + Intel MPI 2021.5 + NetCDF 4.4.1.1) --------------
set +e
source /LUSTRE/HOME/esteban/MITgcm/setup_env.sh
set -e
ulimit -n 6000 || true

EXE=$EXP/build/mitgcmuv
if [[ ! -x "$EXE" ]]; then
    echo "ERROR: no existe el ejecutable $EXE"
    echo "       Compila primero el modelo con MPI (ver cabecera de este script)."
    exit 1
fi

run_stage () {
    local dir=$1 tag=$2 dataf=$3
    echo "-------------------------------------------------------------------"
    echo ">>> $(basename "$dir") - $tag   inicio: $(date)"
    cd "$dir"
    cp -f "$EXE" .
    cp -f "$dataf" data
    rm -f STDOUT.* STDERR.* "output_${tag}.txt" 2>/dev/null || true

    time mpirun -n "$NP" ./mitgcmuv > "output_${tag}.txt" 2>&1

    if ! grep -q "NORMAL END" "output_${tag}.txt"; then
        echo "ERROR: $(basename "$dir") $tag NO termino con NORMAL END"
        echo "----- ultimas lineas de output_${tag}.txt -----"
        tail -40 "output_${tag}.txt"
        exit 2
    fi
    local tmin tmax
    tmax=$(grep "dynstat_theta_max" STDOUT.0000 2>/dev/null | tail -1 | awk '{print $NF}')
    tmin=$(grep "dynstat_theta_min" STDOUT.0000 2>/dev/null | tail -1 | awk '{print $NF}')
    echo "    theta_min/max final = ${tmin:-NA} / ${tmax:-NA}"
    echo "<<< $(basename "$dir") - $tag   fin: $(date)"
}

STAGE1_PICKUP="pickup.0000007200.data"

for DIR in "$EXP/run_expand" "$EXP/run_expand_nobay"; do
    echo "==================================================================="
    echo "### CASO: $(basename "$DIR") ###"
    cd "$DIR"

    if [ -f "$STAGE1_PICKUP" ] && grep -q "NORMAL END" output_stage1.txt 2>/dev/null; then
        echo "  [skip] etapa 1 ya completa ($STAGE1_PICKUP presente)"
    else
        rm -f pickup* PHref* RhoRef.* 2>/dev/null || true
        rm -rf mnc_* OUT_stage1 2>/dev/null || true
        run_stage "$DIR" stage1 "$DIR/data.stage1"
        if [ ! -f "$STAGE1_PICKUP" ]; then
            echo "ERROR: la etapa 1 en $(basename "$DIR") no produjo $STAGE1_PICKUP"
            exit 3
        fi
    fi

    if ls mnc_* >/dev/null 2>&1; then
        mkdir -p OUT_stage1
        for m in mnc_*; do mv "$m" OUT_stage1/; done
    fi

    if grep -q "NORMAL END" output_stage2.txt 2>/dev/null; then
        echo "  [skip] etapa 2 ya completa"
    else
        run_stage "$DIR" stage2 "$DIR/data.stage2"
        mkdir -p OUT_stage2
        for m in mnc_*; do [ -e "$m" ] && mv "$m" OUT_stage2/; done
    fi

    echo "### $(basename "$DIR"): 2 etapas COMPLETAS ###"
done

echo "==================================================================="
echo "TODAS LAS SIMULACIONES (DOS CAPAS, con y sin bahia, 2 etapas) FINALIZADAS: $(date)"
