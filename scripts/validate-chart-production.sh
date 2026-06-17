#!/usr/bin/env bash
set -euo pipefail

chart_dir="${CHART_DIR:-charts/nantian-gw}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

default_render="$tmp_dir/default.yaml"
experimental_render="$tmp_dir/feature-mode-experimental.yaml"
experimental_crd_render="$tmp_dir/experimental-crds.yaml"
experimental_crd_include_render="$tmp_dir/experimental-crds-include.yaml"
standard_crd_render="$tmp_dir/standard-crds.yaml"
standard_crd_include_render="$tmp_dir/standard-crds-include.yaml"
no_crd_render="$tmp_dir/no-crds.yaml"
certs_render="$tmp_dir/certs.yaml"
custom_namespace_render="$tmp_dir/custom-namespace.yaml"
dashboard_disabled_render="$tmp_dir/dashboard-disabled.yaml"
dashboard_override_render="$tmp_dir/dashboard-override.yaml"
dashboard_ingress_render="$tmp_dir/dashboard-ingress.yaml"
dashboard_ingress_tls_invalid="$tmp_dir/dashboard-ingress-tls-invalid.out"
dashboard_sa_missing_name="$tmp_dir/dashboard-sa-missing-name.out"
self_signed_tls_render="$tmp_dir/self-signed-tls.yaml"
cert_manager_render="$tmp_dir/cert-manager.yaml"
cert_manager_missing_issuer="$tmp_dir/cert-manager-missing-issuer.out"
cert_conflict_render="$tmp_dir/cert-conflict.out"
tls_paths_render="$tmp_dir/tls-paths.yaml"
session_shared_render="$tmp_dir/session-shared.rendered.yaml"
session_existing_render="$tmp_dir/session-existing.rendered.yaml"
session_override_render="$tmp_dir/session-override.rendered.yaml"
dev_render="$tmp_dir/values-dev.rendered.yaml"
staging_render="$tmp_dir/values-staging.rendered.yaml"
production_render="$tmp_dir/values-production.rendered.yaml"
ai_gateway_render="$tmp_dir/values-ai-gateway.rendered.yaml"
service_monitor_render="$tmp_dir/service-monitor.rendered.yaml"

python3 - "$chart_dir/values.yaml" <<'PY'
import sys
from pathlib import Path

import yaml

values = yaml.safe_load(Path(sys.argv[1]).read_text())
if values.get("featureMode") != "standard":
    raise SystemExit("values.yaml featureMode default must be standard")
gateway_api = values.get("gatewayAPI") or {}
if gateway_api.get("channel") != "standard":
    raise SystemExit("values.yaml gatewayAPI.channel default must be standard")
PY

bash scripts/test-version-docs.sh

helm lint "$chart_dir"

helm template nantian-gw "$chart_dir" --namespace nantian-gw > "$default_render"
grep -q 'enableExperimentalGateway: false' "$default_render"
grep -q 'enableAiGateway: false' "$default_render"
grep -q 'dashboard:' "$default_render"
grep -q 'name: nantian-gw-dataplane-admin-auth' "$default_render"
grep -q 'mountPath: /etc/nantian-gw/admin-auth' "$default_render"
grep -q 'bearerTokenFile: /etc/nantian-gw/admin-auth/token' "$default_render"
grep -q 'mountPath: /etc/nantian-gw/dataplane-admin-auth' "$default_render"
grep -q 'bearerTokenFile: /etc/nantian-gw/dataplane-admin-auth/token' "$default_render"
if grep -q 'kind: CustomResourceDefinition' "$default_render"; then
  echo "default production render unexpectedly contains Gateway API CRDs" >&2
  exit 1
fi
if grep -q 'name: tcproutes.gateway.networking.k8s.io' "$default_render"; then
  echo "default render unexpectedly contains experimental TCPRoute CRD" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  -f "$chart_dir/values-dev.yaml" > "$dev_render"
grep -q 'enableExperimentalGateway: false' "$dev_render"
grep -q 'enableAiGateway: false' "$dev_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  -f "$chart_dir/values-staging.yaml" > "$staging_render"
grep -q 'enableExperimentalGateway: false' "$staging_render"
grep -q 'enableAiGateway: false' "$staging_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  -f "$chart_dir/values-production.yaml" > "$production_render"
grep -q 'enableExperimentalGateway: false' "$production_render"
grep -q 'enableAiGateway: false' "$production_render"
grep -q 'image: ghcr.io/nantian-gw/nantian-controlplane:sha-8737dc3' "$production_render"
grep -q 'image: ghcr.io/nantian-gw/dataplane:sha-9670107' "$production_render"
grep -q 'image: ghcr.io/nantian-gw/dashboard:sha-af29925' "$production_render"
if grep -Eq 'image: ghcr\.io/nantian-gw/(nantian-controlplane|dataplane|dashboard):latest' "$production_render"; then
  echo "production preset must not render mutable latest component images" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  -f "$chart_dir/values-ai-gateway.yaml" > "$ai_gateway_render"
grep -q 'enableExperimentalGateway: true' "$ai_gateway_render"
grep -q 'enableAiGateway: true' "$ai_gateway_render"

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
if grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$standard_crd_render"; then
  echo "standard Gateway API CRDs unexpectedly rendered from templates" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --include-crds \
  --set gatewayAPI.installCRDs=true > "$standard_crd_include_render"
grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$standard_crd_include_render"
grep -q 'gateway.networking.k8s.io/channel: standard' "$standard_crd_include_render"
if grep -q 'name: tcproutes.gateway.networking.k8s.io' "$standard_crd_include_render"; then
  echo "standard Gateway API CRDs unexpectedly include TCPRoute" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set gatewayAPI.installCRDs=true \
  --set gatewayAPI.channel=experimental > "$experimental_crd_render"
grep -q 'name: tcproutes.gateway.networking.k8s.io' "$experimental_crd_render"
grep -q 'name: udproutes.gateway.networking.k8s.io' "$experimental_crd_render"
grep -q 'name: xbackendtrafficpolicies.gateway.networking.x-k8s.io' "$experimental_crd_render"
grep -q 'name: xmeshes.gateway.networking.x-k8s.io' "$experimental_crd_render"
if grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$experimental_crd_render"; then
  echo "experimental templated CRD render unexpectedly contains standard bundle" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --include-crds \
  --set gatewayAPI.installCRDs=true \
  --set gatewayAPI.channel=experimental > "$experimental_crd_include_render"
grep -q 'name: gatewayclasses.gateway.networking.k8s.io' "$experimental_crd_include_render"
grep -q 'name: tcproutes.gateway.networking.k8s.io' "$experimental_crd_include_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.generate=true > "$certs_render"

helm template customrel "$chart_dir" --namespace release-ns \
  --set nameOverride=customgw \
  --set namespace.create=true \
  --set namespace.name=workload-ns > "$custom_namespace_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dashboard.enabled=false > "$dashboard_disabled_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dashboard.enabled=false \
  --set controlplane.config.dashboard.enabled=true > "$dashboard_override_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dashboard.ingress.enabled=true \
  --set dashboard.ingress.className=nginx \
  --set dashboard.ingress.host=dashboard.example.com \
  --set dashboard.ingress.tls.enabled=true \
  --set dashboard.ingress.tls.secretName=dashboard-example-tls \
  --set 'dashboard.ingress.fromNamespaces[0]=ingress-nginx' > "$dashboard_ingress_render"

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dashboard.ingress.enabled=true \
  --set dashboard.ingress.tls.enabled=true > "$dashboard_ingress_tls_invalid" 2>&1; then
  echo "dashboard ingress TLS without secretName unexpectedly passed schema validation" >&2
  exit 1
fi

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dashboard.serviceAccount.create=false > "$dashboard_sa_missing_name" 2>&1; then
  echo "dashboard serviceAccount.create=false without name unexpectedly passed schema validation" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.generate=true \
  --set controlplane.grpcTLS.enabled=true \
  --set controlplane.grpcTLS.requireClientCert=true \
  --set dataplane.xdsTLS.enabled=true > "$self_signed_tls_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.certManager.enabled=true \
  --set certs.certManager.issuerRef.name=nantian-ca \
  --set controlplane.grpcTLS.enabled=true \
  --set controlplane.grpcTLS.requireClientCert=true \
  --set dataplane.xdsTLS.enabled=true > "$cert_manager_render"

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.certManager.enabled=true > "$cert_manager_missing_issuer" 2>&1; then
  echo "cert-manager mode without issuerRef.name unexpectedly passed schema validation" >&2
  exit 1
fi

if helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set certs.generate=true \
  --set certs.certManager.enabled=true \
  --set certs.certManager.issuerRef.name=nantian-ca > "$cert_conflict_render" 2>&1; then
  echo "self-signed and cert-manager certificate modes unexpectedly passed together" >&2
  exit 1
fi

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set controlplane.grpcTLS.enabled=true \
  --set dataplane.xdsTLS.enabled=true > "$tls_paths_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dataplane.sessionPersistence.sharedSecret=sticky-secret \
  --set dataplane.sessionPersistence.secretKey=sticky-key > "$session_shared_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dataplane.sessionPersistence.existingSecret=sticky-secret \
  --set dataplane.sessionPersistence.secretKey=sticky-key > "$session_existing_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set dataplane.sessionPersistence.existingSecret=sticky-secret \
  --set dataplane.sessionPersistence.secretKey=sticky-key \
  --set dataplane.config.sessionPersistence.secretKeyFile=/custom/session/key > "$session_override_render"

helm template nantian-gw "$chart_dir" --namespace nantian-gw \
  --set serviceMonitor.enabled=true \
  --set 'serviceMonitor.fromNamespaces[0]=monitoring' > "$service_monitor_render"

python3 - "$default_render" "$no_crd_render" "$standard_crd_render" "$experimental_crd_render" "$certs_render" "$custom_namespace_render" "$dashboard_disabled_render" "$dashboard_override_render" "$dashboard_ingress_render" "$self_signed_tls_render" "$cert_manager_render" "$tls_paths_render" "$session_shared_render" "$session_existing_render" "$session_override_render" "$service_monitor_render" <<'PY'
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


def docs_by_kind(path, kind):
    return [
        doc
        for doc in load_safe(path)
        if isinstance(doc, dict) and doc.get("kind") == kind
    ]


def named_doc(path, kind, name):
    for doc in docs_by_kind(path, kind):
        if doc.get("metadata", {}).get("name") == name:
            return doc
    raise SystemExit(f"{kind}/{name} not found in {path}")


def network_policy_allows_namespace(path, policy_name, namespace_name, port):
    policy = named_doc(path, "NetworkPolicy", policy_name)
    for rule in policy["spec"].get("ingress", []):
        has_namespace = any(
            peer.get("namespaceSelector", {})
            .get("matchLabels", {})
            .get("kubernetes.io/metadata.name")
            == namespace_name
            for peer in rule.get("from", [])
        )
        has_port = any(item.get("port") == port for item in rule.get("ports", []))
        if has_namespace and has_port:
            return True
    return False


def dataplane_config(path):
    configmap = named_doc(path, "ConfigMap", "nantian-gw-dataplane-config")
    return yaml.safe_load(configmap["data"]["config.yaml"])


def assert_controlplane_grpc_tls(config, message_prefix):
    grpc_tls = config.get("grpcTLS")
    if not isinstance(grpc_tls, dict):
        raise SystemExit(f"{message_prefix} must render grpcTLS config")
    if grpc_tls.get("enabled") is not True:
        raise SystemExit(f"{message_prefix} grpcTLS.enabled must render true when chart TLS is enabled")
    if grpc_tls.get("certPath") != "/etc/nantian-gw/grpc-tls/tls.crt":
        raise SystemExit(f"{message_prefix} grpcTLS.certPath default mismatch")
    if grpc_tls.get("keyPath") != "/etc/nantian-gw/grpc-tls/tls.key":
        raise SystemExit(f"{message_prefix} grpcTLS.keyPath default mismatch")
    if grpc_tls.get("clientCAPath") != "/etc/nantian-gw/grpc-tls/ca.crt":
        raise SystemExit(f"{message_prefix} grpcTLS.clientCAPath default mismatch")


def assert_dataplane_xds_tls(config, message_prefix):
    xds_tls = config.get("xdsTls")
    if not isinstance(xds_tls, dict):
        raise SystemExit(f"{message_prefix} must render xdsTls config")
    if xds_tls.get("enabled") is not True:
        raise SystemExit(f"{message_prefix} xdsTls.enabled must render true when chart TLS is enabled")
    if xds_tls.get("caPath") != "/etc/nantian-gw/xds-tls/ca.crt":
        raise SystemExit(f"{message_prefix} xdsTls.caPath default mismatch")
    if xds_tls.get("certPath") != "/etc/nantian-gw/xds-tls/tls.crt":
        raise SystemExit(f"{message_prefix} xdsTls.certPath default mismatch")
    if xds_tls.get("keyPath") != "/etc/nantian-gw/xds-tls/tls.key":
        raise SystemExit(f"{message_prefix} xdsTls.keyPath default mismatch")


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
configmaps = {
    doc["metadata"]["name"]: doc
    for doc in docs
    if isinstance(doc, dict) and doc.get("kind") == "ConfigMap"
}

for deployment_name, deployment in deployments.items():
    selector = deployment["spec"]["selector"]["matchLabels"]
    template_labels = deployment["spec"]["template"]["metadata"]["labels"]
    missing = {
        key: value
        for key, value in selector.items()
        if template_labels.get(key) != value
    }
    if missing:
        raise SystemExit(
            f"{deployment_name} selector labels missing from pod template: {missing}"
        )

controlplane_config = yaml.safe_load(
    configmaps["nantian-gw-controlplane-config"]["data"]["config.yaml"]
)
expected_admin_url = (
    "http://nantian-gw-dataplane-admin.nantian-gw.svc.cluster.local:19080"
)
actual_admin_url = controlplane_config["dashboardApi"]["dataplaneAdminUrl"]
if actual_admin_url != expected_admin_url:
    raise SystemExit(
        "controlplane dashboardApi.dataplaneAdminUrl mismatch: "
        f"expected {expected_admin_url}, got {actual_admin_url}"
    )
dashboard_cfg = controlplane_config.get("dashboard") or {}
if dashboard_cfg.get("enabled") is not True:
    raise SystemExit("default controlplane dashboard.enabled must render as true")
default_service_accounts = {
    doc["metadata"]["name"]: doc
    for doc in docs_by_kind(sys.argv[1], "ServiceAccount")
}
if "nantian-gw-dashboard" not in default_service_accounts:
    raise SystemExit("default render must create nantian-gw-dashboard ServiceAccount")
dashboard_deployment = deployments["nantian-gw-dashboard"]
dashboard_pod_spec = dashboard_deployment["spec"]["template"]["spec"]
if dashboard_pod_spec.get("serviceAccountName") != "nantian-gw-dashboard":
    raise SystemExit("dashboard deployment must use nantian-gw-dashboard ServiceAccount")
if dashboard_pod_spec.get("automountServiceAccountToken") is not False:
    raise SystemExit("dashboard deployment must disable service account token automount by default")
dashboard_caps = dashboard_cfg.get("capabilities") or {}
for key in [
    "aiOverview",
    "aiServices",
    "aiTokenPolicies",
    "aiCost",
    "aiTraces",
    "aiUsage",
    "wasmPlugins",
    "chatbot",
]:
    if dashboard_caps.get(key) is not True:
        raise SystemExit(f"default controlplane dashboard.capabilities.{key} must render as true")

images = []
for deployment in deployments.values():
    for container in deployment["spec"]["template"]["spec"].get("containers", []):
        images.append(container.get("image", ""))
for pod in pods.values():
    for container in pod["spec"].get("containers", []):
        images.append(container.get("image", ""))

dataplane = deployments["nantian-gw-dataplane"]
dp_pod = dataplane["spec"]["template"]["spec"]
dp_env_names = {
    env.get("name")
    for env in dp_pod["containers"][0].get("env", [])
    if isinstance(env, dict)
}
if "AEG_NODE_ID" not in dp_env_names:
    raise SystemExit("dataplane container missing AEG_NODE_ID downward API env")
if "PGW_NODE_ID" in dp_env_names:
    raise SystemExit("dataplane container renders obsolete PGW_NODE_ID env")

shared_dp = dataplane_config(sys.argv[13])
shared_session = shared_dp.get("sessionPersistence") or {}
if shared_session.get("secretKeyFile") != "/etc/nantian-gw/session-persistence/sticky-key":
    raise SystemExit(
        "shared-secret dataplane config must render sessionPersistence.secretKeyFile from the mounted Secret"
    )

existing_dp = dataplane_config(sys.argv[14])
existing_session = existing_dp.get("sessionPersistence") or {}
if existing_session.get("secretKeyFile") != "/etc/nantian-gw/session-persistence/sticky-key":
    raise SystemExit(
        "existing-secret dataplane config must render sessionPersistence.secretKeyFile from the mounted Secret"
    )

override_dp = dataplane_config(sys.argv[15])
override_session = override_dp.get("sessionPersistence") or {}
if override_session.get("secretKeyFile") != "/custom/session/key":
    raise SystemExit(
        "explicit dataplane.config.sessionPersistence.secretKeyFile must not be overwritten"
    )

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

custom_docs = load_safe(sys.argv[6])
custom_configmaps = {
    doc["metadata"]["name"]: doc
    for doc in custom_docs
    if isinstance(doc, dict) and doc.get("kind") == "ConfigMap"
}
custom_controlplane_config = yaml.safe_load(
    custom_configmaps["customgw-controlplane-config"]["data"]["config.yaml"]
)
expected_custom_admin_url = (
    "http://customgw-dataplane-admin.workload-ns.svc.cluster.local:19080"
)
actual_custom_admin_url = custom_controlplane_config["dashboardApi"]["dataplaneAdminUrl"]
if actual_custom_admin_url != expected_custom_admin_url:
    raise SystemExit(
        "custom controlplane dashboardApi.dataplaneAdminUrl mismatch: "
        f"expected {expected_custom_admin_url}, got {actual_custom_admin_url}"
    )

dashboard_disabled_docs = load_safe(sys.argv[7])
dashboard_disabled_configmaps = {
    doc["metadata"]["name"]: doc
    for doc in dashboard_disabled_docs
    if isinstance(doc, dict) and doc.get("kind") == "ConfigMap"
}
dashboard_disabled_config = yaml.safe_load(
    dashboard_disabled_configmaps["nantian-gw-controlplane-config"]["data"]["config.yaml"]
)
if dashboard_disabled_config["dashboard"]["enabled"] is not False:
    raise SystemExit(
        "controlplane dashboard.enabled must follow chart dashboard.enabled=false by default"
    )

dashboard_override_docs = load_safe(sys.argv[8])
dashboard_override_configmaps = {
    doc["metadata"]["name"]: doc
    for doc in dashboard_override_docs
    if isinstance(doc, dict) and doc.get("kind") == "ConfigMap"
}
dashboard_override_config = yaml.safe_load(
    dashboard_override_configmaps["nantian-gw-controlplane-config"]["data"]["config.yaml"]
)
if dashboard_override_config["dashboard"]["enabled"] is not True:
    raise SystemExit(
        "explicit controlplane.config.dashboard.enabled=true override must win over chart dashboard.enabled=false"
    )

dashboard_ingress = named_doc(sys.argv[9], "Ingress", "nantian-gw-dashboard")
if dashboard_ingress["spec"].get("ingressClassName") != "nginx":
    raise SystemExit("dashboard ingress must render ingressClassName=nginx")
rules = dashboard_ingress["spec"].get("rules", [])
if not rules or rules[0].get("host") != "dashboard.example.com":
    raise SystemExit("dashboard ingress must render configured host")
http_rule = rules[0].get("http")
if not isinstance(http_rule, dict):
    raise SystemExit("dashboard ingress must render an HTTP rule")
paths = http_rule.get("paths", [])
if not paths:
    raise SystemExit("dashboard ingress must render at least one HTTP path")
backend = paths[0].get("backend", {}).get("service")
if not isinstance(backend, dict):
    raise SystemExit("dashboard ingress must render a service backend for the first HTTP path")
if backend.get("name") != "nantian-gw-dashboard":
    raise SystemExit("dashboard ingress must target nantian-gw-dashboard Service")
if backend.get("port", {}).get("number") != 3000:
    raise SystemExit("dashboard ingress must target dashboard service port 3000")
tls = dashboard_ingress["spec"].get("tls", [])
if not tls or tls[0].get("secretName") != "dashboard-example-tls":
    raise SystemExit("dashboard ingress must render configured TLS secret")

dashboard_np = named_doc(sys.argv[9], "NetworkPolicy", "nantian-gw-dashboard")
ingress_rules = dashboard_np["spec"].get("ingress", [])
allowed_namespaces = []
for rule in ingress_rules:
    for peer in rule.get("from", []):
        match_labels = peer.get("namespaceSelector", {}).get("matchLabels", {})
        if "kubernetes.io/metadata.name" in match_labels:
            allowed_namespaces.append(match_labels["kubernetes.io/metadata.name"])
if "ingress-nginx" not in allowed_namespaces:
    raise SystemExit("dashboard NetworkPolicy must allow configured ingress namespace")

self_signed_configmaps = {
    doc["metadata"]["name"]: doc
    for doc in docs_by_kind(sys.argv[10], "ConfigMap")
}
self_signed_cp = yaml.safe_load(
    self_signed_configmaps["nantian-gw-controlplane-config"]["data"]["config.yaml"]
)
assert_controlplane_grpc_tls(self_signed_cp, "controlplane")

self_signed_dp = yaml.safe_load(
    self_signed_configmaps["nantian-gw-dataplane-config"]["data"]["config.yaml"]
)
assert_dataplane_xds_tls(self_signed_dp, "dataplane")

self_signed_secrets = {
    doc["metadata"]["name"]: doc
    for doc in docs_by_kind(sys.argv[10], "Secret")
}
server_secret = self_signed_secrets["nantian-gw-grpc-server-tls"]
if "ca.crt" not in server_secret.get("data", {}):
    raise SystemExit("self-signed server TLS Secret must include ca.crt")
client_secret = self_signed_secrets["nantian-gw-grpc-client-tls"]
for key in ["ca.crt", "tls.crt", "tls.key"]:
    if key not in client_secret.get("data", {}):
        raise SystemExit(f"self-signed client TLS Secret missing {key}")

certificates = {
    doc["metadata"]["name"]: doc
    for doc in docs_by_kind(sys.argv[11], "Certificate")
}
for certificate_name, secret_name, usage in [
    ("nantian-gw-grpc-server-tls", "nantian-gw-grpc-server-tls", "server auth"),
    ("nantian-gw-grpc-client-tls", "nantian-gw-grpc-client-tls", "client auth"),
]:
    certificate = certificates.get(certificate_name)
    if certificate is None:
        raise SystemExit(f"cert-manager Certificate {certificate_name} missing")
    spec = certificate.get("spec", {})
    if spec.get("secretName") != secret_name:
        raise SystemExit(f"Certificate {certificate_name} secretName mismatch")
    issuer_ref = spec.get("issuerRef", {})
    if issuer_ref.get("name") != "nantian-ca":
        raise SystemExit(f"Certificate {certificate_name} issuerRef.name mismatch")
    if usage not in spec.get("usages", []):
        raise SystemExit(f"Certificate {certificate_name} missing usage {usage}")

tls_paths_configmaps = {
    doc["metadata"]["name"]: doc
    for doc in docs_by_kind(sys.argv[12], "ConfigMap")
}
tls_paths_cp = yaml.safe_load(
    tls_paths_configmaps["nantian-gw-controlplane-config"]["data"]["config.yaml"]
)
assert_controlplane_grpc_tls(tls_paths_cp, "tls-paths controlplane")

tls_paths_dp = yaml.safe_load(
    tls_paths_configmaps["nantian-gw-dataplane-config"]["data"]["config.yaml"]
)
assert_dataplane_xds_tls(tls_paths_dp, "tls-paths dataplane")

service_monitor = named_doc(sys.argv[16], "ServiceMonitor", "nantian-gw-controlplane")
selector = service_monitor["spec"]["selector"]["matchLabels"]
if selector.get("app.kubernetes.io/component") != "controlplane":
    raise SystemExit(
        "controlplane ServiceMonitor must select only controlplane metrics Service"
    )
if selector.get("gateway.nantian.dev/service-role") != "metrics":
    raise SystemExit("controlplane ServiceMonitor must select metrics service-role")

if not network_policy_allows_namespace(
    sys.argv[16], "nantian-gw-controlplane", "monitoring", 18082
):
    raise SystemExit(
        "controlplane NetworkPolicy must allow configured monitoring namespace to metrics port"
    )
if not network_policy_allows_namespace(
    sys.argv[16], "nantian-gw-dataplane", "monitoring", 19080
):
    raise SystemExit(
        "dataplane NetworkPolicy must allow configured monitoring namespace to metrics/admin port"
    )
PY

if grep -Eq 'gen(CA|SignedCert).*\b3650\b' "$chart_dir/templates/certs.yaml"; then
  echo "certs.yaml must not hard-code 3650-day self-signed certificates" >&2
  exit 1
fi

if grep -q 'lookup "v1" "Secret" \.Release\.Namespace' "$chart_dir/templates/_helpers.tpl"; then
  echo "dashboard auth secret lookup must use the chart resource namespace, not .Release.Namespace" >&2
  exit 1
fi
