#!/usr/bin/env bash
# Full reproduction of the function-encoder (FE) rollout comparison against
# NCLaw's own trajectories: all 4 materials (sand, jelly, water, plasticine),
# every scene (dataset, time, vel_0001, vel_0007, vel_0008, and the held-out
# mesh shape scene) and every accepted FE leg per material.
#
# Companion to run_euclid_compare.sh: that script reproduces the known-form
# (EUCLID) comparison; this one reproduces the function-encoder identification
# + rollout row, experiments/fe_ls/cross.py. Both read the SAME ingested NCLaw
# trajectories under out/nclaw_cross_generalize/dumps/<material>_*_truth.npz
# and both roll out through experiments/nclaw/suite.py's run_scene, so this
# script inherits the shape-dependent particle_clip_cells fix
# (NCLAW_SHAPE_CLIP_BOUND, keyed by the scene name inside run_scene itself)
# with no changes needed here -- verified 2026-09-11.
#
# Cache: out/fe_ls_cross/*.npz is cross.py's own rollout cache
# ("if not pred.exists(): run_scene(...)"); governs simulate_eval_s. It is
# NOT cleared by default, so a plain rerun just resumes/extends whatever is
# already on disk (e.g. a device switch mid-run leaves a device-mixed cache --
# harmless for correctness, since the dumps don't record which device wrote
# them, but not a clean timing comparison). Pass --clean for a genuinely
# from-scratch timed run. identify_*_fe legs have no on-disk cache: they
# recompute every run (~35s/material), so there is nothing to clear there.
#
# Save format: np.savez (uncompressed) throughout -- DumpWriter's
# compress=False default, unchanged; nothing here overrides it. Prediction
# dumps are written with xonly=True (positions and times only, no v/L/stress/
# F/volume/active/mass), the same choice experiments.nclaw.compare makes for
# its own prediction dumps, since nclaw_position_mse reads back x alone.
#
# Usage (from the repo root):
#   tmux new -s fe_ls_cross
#   ./run_fe_ls_cross.sh                 # GPU (cuda:0 by default), resumable
#   ./run_fe_ls_cross.sh --clean         # wipe the rollout cache first
#   ./run_fe_ls_cross.sh --device=cpu    # override device
#   ./run_fe_ls_cross.sh sand water      # only these materials
#   # detach:   Ctrl-b d
#   # reattach: tmux attach -t fe_ls_cross
#   # tail progress from another shell without attaching:
#   #   tail -f out/fe_ls_cross/timing_logs/<material>.log
#
# Results: out/fe_ls_cross/results.json (each material's key, including its
# timing_breakdown_s, is overwritten as that material finishes -- readable
# mid-run for whichever materials are already done). Per-material stdout logs:
# out/fe_ls_cross/timing_logs/<material>.log.

set -e
cd "$(dirname "$0")"

DEVICE="cuda:0"
CLEAN=0
MATERIALS=()
for arg in "$@"; do
  case "$arg" in
    --device=*) DEVICE="${arg#--device=}" ;;
    --clean) CLEAN=1 ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    *) MATERIALS+=("$arg") ;;
  esac
done
if [ ${#MATERIALS[@]} -eq 0 ]; then
  MATERIALS=(sand jelly water plasticine)
fi

LOG_DIR=out/fe_ls_cross/timing_logs
mkdir -p "$LOG_DIR" out/fe_ls_cross

if [ "$CLEAN" = "1" ]; then
  echo "[fe_ls_cross] --clean: wiping the rollout cache for a from-scratch run"
  rm -f out/fe_ls_cross/*.npz
  rm -f out/fe_ls_cross/results.json
fi

echo "[fe_ls_cross] device=$DEVICE materials=${MATERIALS[*]}"
.venv/bin/python -m warpmpm.prewarm --device="$DEVICE"

run() {
  local material=$1
  local log="$LOG_DIR/${material}.log"
  echo "[fe_ls_cross] $material -> $log"
  .venv/bin/python -m experiments.fe_ls.cross --device="$DEVICE" "$material" \
    2>&1 | tee "$log"
}

for m in "${MATERIALS[@]}"; do
  run "$m"
done

echo
echo "[fe_ls_cross] done -> out/fe_ls_cross/results.json"
