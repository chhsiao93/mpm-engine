#!/usr/bin/env bash
# Ingest NCLaw's truth trajectories into
# out/nclaw_cross_generalize/dumps/<material>_<scene>_truth.npz, the step
# BEFORE run_euclid_compare.sh and run_fe_ls_cross.sh (neither rebuilds them).
# Wraps experiments/nclaw/cross_generalize.py; see its docstring for the
# scene layout and how the manifest is resolved.
#
# Prerequisites:
#   1. The truth runs, generated in the NCLaw clone with NCLaw's OWN venv:
#        cd ../NCLaw && source .venv/bin/activate
#        uv run experiments/scripts/dataset/main.py
#        uv run experiments/scripts/eval/{time,vel,shape}.py --gt
#   2. pyyaml in THIS repo's .venv (reads NCLaw's hydra.yaml; deliberately
#      not declared in pyproject.toml):
#        uv pip install pyyaml
#
# Usage (from the repo root):
#   ./run_nclaw_ingest.sh                      # all 4 materials
#   ./run_nclaw_ingest.sh --material=jelly,sand
#   ./run_nclaw_ingest.sh --force              # re-ingest existing dumps
#   NCLAW_ROOT=/path/to/NCLaw ./run_nclaw_ingest.sh

set -eo pipefail
cd "$(dirname "$0")"

NCLAW_ROOT=${NCLAW_ROOT:-../NCLaw}

.venv/bin/python -c "import yaml" 2>/dev/null || {
  echo "[ingest] pyyaml missing from .venv: uv pip install pyyaml" >&2; exit 1; }

.venv/bin/python -m experiments.nclaw.cross_generalize \
  --log-root "$NCLAW_ROOT/experiments/log" --nclaw-dir "$NCLAW_ROOT" "$@"
