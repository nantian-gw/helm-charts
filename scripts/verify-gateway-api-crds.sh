#!/usr/bin/env bash
set -euo pipefail

chart_dir="${CHART_DIR:-charts/nantian-gw}"

bash scripts/sync-gateway-api-crds.sh

if ! git diff --quiet -- \
  "${chart_dir}/charts/gateway-api-crds-standard/Chart.yaml" \
  "${chart_dir}/charts/gateway-api-crds-standard/crds" \
  "${chart_dir}/templates/gateway-api-crds.yaml"; then
  echo "Gateway API CRDs are stale. Run scripts/sync-gateway-api-crds.sh and commit the result." >&2
  git diff -- \
    "${chart_dir}/charts/gateway-api-crds-standard/Chart.yaml" \
    "${chart_dir}/charts/gateway-api-crds-standard/crds" \
    "${chart_dir}/templates/gateway-api-crds.yaml" >&2
  exit 1
fi
