#!/usr/bin/env bash
# Full reproduction of the NCLaw cross-engine comparison, all 3 tiers x 4
# materials, with per-run timing broken into reconstruct/assemble/fit/
# simulate (each further split into sub-components) and logged individually.
#
# THREE separate caches must all be cleared for a genuinely from-scratch
# timed run, or a component silently reports near-zero and the table
# under-reports:
#   1. out/nclaw_cross_compare/*.npz       -- compare.py's own rollout cache
#      ("if not pred.exists(): run_scene(...)"); governs simulate_eval_s.
#   2. out/nclaw_suite/scan/*.npz          -- rollout_scan.py's per-candidate
#      cache; governs simulate_search_s (sand/plasticine/water positions-only).
#      CONFIRMED by rerunning sand and plasticine twice back-to-back: this is
#      what made the previously-reported 12.8s/21.8s numbers ~3x smaller than
#      a true cold-cache run (~39s/~45s) -- most of the scan's candidate
#      rollouts were already sitting on disk, not GPU/JIT warmup.
#   3. out/nclaw_cross_generalize/dumps/<material>_dataset_truth_no_stress.npz
#      and _positions_only.npz             -- write_tier_dump()'s OWN cache
#      ("if dest.exists(): return dest"), separate from and in ADDITION to
#      write_positions_only_dump/write_no_stress_dump themselves (which do
#      unconditionally recompute once actually called). Left in place, this
#      silently skips field reconstruction and reconstruct_fields_s reports
#      only the small extra pass replay.py runs inside the positions-only
#      sand/plasticine estimator, NOT the real fd_velocity + MLS + npz-write
#      cost.
#
# Warp's own CUDA kernel JIT compile (src/warpmpm/prewarm.py) was RULED OUT
# as a factor here: a prewarm run on this machine showed the standard
# kernels already disk-cached (0.0-0.1s), and simulate_search_s stayed
# ~29-30s across two consecutive cold-cache reruns -- the invariant expected
# from real work, not one-time compilation. Still prewarmed below as cheap
# insurance for a kernel variant (grid size, nclaw_law path) genuinely new to
# this machine.
#
# Each `compare.py` invocation writes/overwrites its own
# out/nclaw_cross_compare/compare_<material>...json, now carrying a
# "timing_breakdown_s" block (reconstruct_fields_s, plus
# reconstruct_tier_dump_detail_s: fd_velocity_s/neighbor_search_s/
# mls_solve_s/volume_mass_s/npz_write_s -- positions-only tier reverted
# 2026-09-05 to the pre-re-neighbour baseline: one frame-0 neighbour search,
# reused for both the L and F moving-least-squares fits, no F integration;
# assemble_equations_s;
# fit_parameters_s; simulate_search_s, plus simulate_search_detail_s and
# simulate_search_device -- scan_parameter() now takes this script's
# --device=cuda:0 (previously always ran on CPU regardless of --device;
# wired through 2026-09-05: rollout_scan.scan_parameter ->
# identify_no_stress.stage_identify_no_stress -> compare.py's device arg);
# simulate_eval_s, plus simulate_eval_detail_s split into
# setup_s/step_s/snapshot_s/finalize_s) plus a full stdout log under
# out/nclaw_cross_compare/timing_logs/. timing_report.py at the end reads
# all 12 of those JSON files into one timing/loss/parameter-error table.
#
# Save format, unchanged and confirmed throughout this pipeline: np.savez
# (uncompressed), never np.savez_compressed, in strip_channels.py's two tier
# writers and in DumpWriter (compress=False is the default and nothing here
# overrides it). ingest.py's one savez_compressed call is the one-time
# NCLaw-folder ingest step, outside this timed pipeline entirely.

set -e
cd "$(dirname "$0")"

LOG_DIR=out/nclaw_cross_compare/timing_logs
DUMPS_DIR=out/nclaw_cross_generalize/dumps
mkdir -p "$LOG_DIR" out/nclaw_cross_compare out/nclaw_suite/scan

echo "[euclid_compare] clearing all 3 caches (rollouts, scan, tier dumps) for a fresh timed run"
rm -f out/nclaw_cross_compare/*.npz
rm -f out/nclaw_cross_compare/compare_*.json
rm -f out/nclaw_suite/scan/*.npz
rm -f "$DUMPS_DIR"/*_dataset_truth_no_stress.npz
rm -f "$DUMPS_DIR"/*_dataset_truth_positions_only.npz

# Cheap insurance for a kernel variant genuinely new to this machine (see the
# note above on why this was ruled out as the main cause of the previous
# discrepancy).
.venv/bin/python -m warpmpm.prewarm --device=cuda:0

run() {
  # run <material> <tier-label-for-logfile> <compare.py args...>
  local material=$1 tier_label=$2; shift 2
  local log="$LOG_DIR/${material}_${tier_label}.log"
  echo "[euclid_compare] $material $tier_label -> $log"
  .venv/bin/python -m experiments.nclaw.compare "$material" "$@" --device=cuda:0 \
    2>&1 | tee "$log"
}

# None tier (full channels)
run plasticine full
run jelly      full
run sand       full
run water      full

# No stress tier
run plasticine nostress --no-stress
run jelly      nostress --no-stress
run sand       nostress --no-stress
run water      nostress --no-stress

# Positions-only tier
run plasticine positionsonly --positions-only
run jelly      positionsonly --positions-only
run sand       positionsonly --positions-only
run water      positionsonly --positions-only

# comparison tables (unchanged)
.venv/bin/python -m experiments.nclaw.no_stress_table --tier full --out out/nclaw_cross_compare/table_full.md
.venv/bin/python -m experiments.nclaw.no_stress_table --tier nostress --out out/nclaw_cross_compare/table_nostress.md
.venv/bin/python -m experiments.nclaw.no_stress_table --tier positionsonly --out out/nclaw_cross_compare/table_positionsonly.md

# timing / loss / parameter-error table across all 12 runs
.venv/bin/python -m experiments.nclaw.timing_report --out out/nclaw_cross_compare/timing_report.md

# shape-scene truth_theta simulate time, per material

# LOG_DIR=out/nclaw_cross_compare/timing_logs
# mkdir -p "$LOG_DIR"

# .venv/bin/python -m warpmpm.prewarm --device=cuda:0

# for m in jelly plasticine sand water; do
#   log="$LOG_DIR/${m}_shape_timing.log"
#   if [ -f "$log" ]; then
#     echo "[timing] $m: $log already exists, skipping (rm it to re-measure)"
#     continue
#   fi
#   case $m in
#     jelly)       shape_file=jelly_shape_armadillo_truth_theta_nclawbc_sub1.npz ;;
#     plasticine)  shape_file=plasticine_shape_bunny_truth_theta_nclawbc.npz ;;
#     sand)        shape_file=sand_shape_blub_truth_theta_nclawbc_nclawlaw_sub1.npz ;;
#     water)       shape_file=water_shape_spot_truth_theta_nclawbc_nclawlaw.npz ;;
#   esac
#   rm -f "out/nclaw_cross_compare/$shape_file"
#   .venv/bin/python -m experiments.nclaw.compare $m --device=cuda:0 2>&1 | tee "$log"
# done

# echo
# echo "=== shape-scene truth_theta simulate time ==="
# grep -h '\[gen\] wrote.*shape.*truth_theta' "$LOG_DIR"/*_shape_timing.log
