#!/usr/bin/env bash
set -euo pipefail

chart_dir="charts/nantian-gw"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

default_render="$tmp_dir/default.yaml"
experimental_render="$tmp_dir/feature-mode-experimental.yaml"
experimental_crd_render="$tmp_dir/experimental-crds.yaml"
standard_crd_render="$tmp_dir/standard-crds.yaml"
no_crd_render="$tmp_dir/no-crds.yaml"
certs_render="$tmp_dir/certs.yaml"

helm lint "$chart_dir"

helm template nantian-gw "$chart_dir" --namespace nantian-gw > "$default_render"
grep -q 'enableExperimentalGateway: false' "$default_render"
grep -q 'enableAiGateway: false' "$default_render"
if grep -q 'kind: CustomResourceDefinition' "$default_render"; then
  echo "default production render unexpectedly contains Gateway API CRDs" >&2
  exit 1
fi
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
  --set gatewayAPI.installCRDs=true > "$standard_crd_render"
grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$standard_crd_render"
grep -q 'gateway.networking.k8s.io/channel: standard' "$standard_crd_render"
if grep -q 'name: tcproutes.gateway.networking.k8s.io' "$standard_crd_render"; then
  echo "standard Gateway API CRDs unexpectedly include TCPRoute" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set gatewayAPI.installCRDs=true \
  --set gatewayAPI.channel=experimental > "$experimental_crd_render"
grep -q 'name: tcproutes.gateway.networking.k8s.io' "$experimental_crd_render"
grep -q 'gateway.networking.k8s.io/channel: experimental' "$experimental_crd_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.generate=true > "$certs_render"

python3 - "$default_render" "$no_crd_render" "$standard_crd_render" "$experimental_crd_render" "$certs_render" <<'PY'
import sys
from pathlib import Path

import yaml


class DupCheckLoader(yaml.SafeLoader):
    pass


def construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            mark = key_node.start_mark
            raise yaml.YAMLError(
                f"duplicate key {key!r} at line {mark.line + 1}, column {mark.column + 1}"
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DupCheckLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_mapping,
)


def load_strict(path):
    text = Path(path).read_text()
    return list(yaml.load_all(text, Loader=DupCheckLoader))


def load_safe(path):
    return list(yaml.safe_load_all(Path(path).read_text()))


for render_path in sys.argv[1:]:
    load_strict(render_path)

docs = load_safe(sys.argv[1])
deployments = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if isinstance(doc, dict) and doc.get("kind") == "Deployment"
}
pods = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if isinstance(doc, dict) and doc.get("kind") == "Pod"
}

images = []
for deployment in deployments.values():
    for container in deployment["spec"]["template"]["spec"].get("containers", []):
        images.append(container.get("image", ""))
for pod in pods.values():
    for container in pod["spec"].get("containers", []):
        images.append(container.get("image", ""))
latest = [image for image in images if image.endswith(":latest")]
if latest:
    raise SystemExit(f"mutable latest image tags rendered: {', '.join(sorted(latest))}")

dataplane = deployments["nantian-gw-dataplane"]
dp_pod = dataplane["spec"]["template"]["spec"]
dp_pod_sc = dp_pod.get("securityContext", {})
if dp_pod_sc.get("runAsNonRoot") is not True:
    raise SystemExit("dataplane pod missing runAsNonRoot=true")
if dp_pod_sc.get("runAsUser") != 65532:
    raise SystemExit("dataplane pod missing runAsUser=65532")
if dp_pod_sc.get("seccompProfile", {}).get("type") != "RuntimeDefault":
    raise SystemExit("dataplane pod missing RuntimeDefault seccompProfile")
sysctls = dp_pod_sc.get("sysctls", [])
if not any(item.get("name") == "net.ipv4.ip_unprivileged_port_start" for item in sysctls):
    raise SystemExit("dataplane pod missing low-port sysctl")

dp_container_sc = dp_pod["containers"][0].get("securityContext", {})
if dp_container_sc.get("allowPrivilegeEscalation") is not False:
    raise SystemExit("dataplane container allows privilege escalation")
if dp_container_sc.get("readOnlyRootFilesystem") is not True:
    raise SystemExit("dataplane container root filesystem is writable")
capabilities = dp_container_sc.get("capabilities", {})
if "ALL" not in capabilities.get("drop", []):
    raise SystemExit("dataplane container does not drop ALL capabilities")
if "NET_BIND_SERVICE" not in capabilities.get("add", []):
    raise SystemExit("dataplane container missing NET_BIND_SERVICE capability")

test_pod = pods["nantian-gw-test-connection"]
if test_pod["spec"].get("automountServiceAccountToken") is not False:
    raise SystemExit("test pod must disable service account token automount")
if test_pod["spec"].get("securityContext", {}).get("runAsNonRoot") is not True:
    raise SystemExit("test pod missing runAsNonRoot=true")
test_container = test_pod["spec"]["containers"][0]
test_sc = test_container.get("securityContext", {})
if test_sc.get("allowPrivilegeEscalation") is not False:
    raise SystemExit("test container allows privilege escalation")
if "ALL" not in test_sc.get("capabilities", {}).get("drop", []):
    raise SystemExit("test container does not drop ALL capabilities")
if not test_container.get("resources", {}).get("requests"):
    raise SystemExit("test container missing resource requests")
if not test_container.get("resources", {}).get("limits"):
    raise SystemExit("test container missing resource limits")

cert_docs = load_safe(sys.argv[5])
secrets = {
    doc["metadata"]["name"]: doc
    for doc in cert_docs
    if isinstance(doc, dict) and doc.get("kind") == "Secret"
}
for secret_name in [
    "nantian-gw-grpc-ca",
    "nantian-gw-grpc-server-tls",
    "nantian-gw-grpc-client-tls",
]:
    annotations = secrets.get(secret_name, {}).get("metadata", {}).get("annotations", {})
    if annotations.get("helm.sh/resource-policy") != "keep":
        raise SystemExit(f"{secret_name} missing helm.sh/resource-policy=keep")
PY
