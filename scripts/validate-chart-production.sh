#!/usr/bin/env bash
set -euo pipefail

chart_dir="charts/nantian-gw"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

default_render="$tmp_dir/default.yaml"
experimental_render="$tmp_dir/feature-mode-experimental.yaml"
experimental_crd_render="$tmp_dir/experimental-crds.yaml"
no_crd_render="$tmp_dir/no-crds.yaml"

helm lint "$chart_dir"

helm template nantian-gw "$chart_dir" --namespace nantian-gw > "$default_render"
grep -q 'enableExperimentalGateway: false' "$default_render"
grep -q 'enableAiGateway: false' "$default_render"
grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$default_render"
grep -q 'gateway.networking.k8s.io/channel: standard' "$default_render"
if grep -q 'name: tcproutes.gateway.networking.k8s.io' "$default_render"; then
  echo "default render unexpectedly contains experimental TCPRoute CRD" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set featureMode=experimental > "$experimental_render"
grep -q 'enableExperimentalGateway: true' "$experimental_render"
grep -q 'enableAiGateway: false' "$experimental_render"

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set featureMode=invalid > "$tmp_dir/invalid-mode.out" 2>&1; then
  echo "invalid featureMode unexpectedly passed schema validation" >&2
  exit 1
fi

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set controlplane.config.features.enableExperimentalGateway=true > "$tmp_dir/standard-runtime-flag.out" 2>&1; then
  echo "experimental runtime flag unexpectedly passed in standard mode" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set gatewayAPI.installCRDs=false > "$no_crd_render"
if grep -q 'kind: CustomResourceDefinition' "$no_crd_render"; then
  echo "Gateway API CRDs rendered even though gatewayAPI.installCRDs=false" >&2
  exit 1
fi

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set gatewayAPI.channel=invalid > "$tmp_dir/invalid-channel.out" 2>&1; then
  echo "invalid gatewayAPI.channel unexpectedly passed schema validation" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set gatewayAPI.channel=experimental > "$experimental_crd_render"
grep -q 'name: tcproutes.gateway.networking.k8s.io' "$experimental_crd_render"
grep -q 'gateway.networking.k8s.io/channel: experimental' "$experimental_crd_render"
