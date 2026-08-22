#!/usr/bin/env bash
set -euo pipefail

chart_dir="${CHART_DIR:-charts/nantian-gw}"
gateway_api_version="${GATEWAY_API_VERSION:-v1.5.1}"
standard_url="${GATEWAY_API_STANDARD_URL:-https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/standard-install.yaml}"
experimental_url="${GATEWAY_API_EXPERIMENTAL_URL:-https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/experimental-install.yaml}"
standard_dir="${chart_dir}/charts/gateway-api-crds-standard/crds"
standard_chart="${chart_dir}/charts/gateway-api-crds-standard/Chart.yaml"
experimental_template="${chart_dir}/templates/gateway-api-crds.yaml"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

standard_manifest="${tmp_dir}/standard-install.yaml"
experimental_manifest="${tmp_dir}/experimental-install.yaml"

curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 "${standard_url}" -o "${standard_manifest}"
curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 "${experimental_url}" -o "${experimental_manifest}"

python3 - \
  "${standard_manifest}" \
  "${experimental_manifest}" \
  "${standard_dir}" \
  "${standard_chart}" \
  "${experimental_template}" \
  "${gateway_api_version}" <<'PY'
import re
import sys
from pathlib import Path

standard_manifest = Path(sys.argv[1])
experimental_manifest = Path(sys.argv[2])
standard_dir = Path(sys.argv[3])
standard_chart = Path(sys.argv[4])
experimental_template = Path(sys.argv[5])
gateway_api_version = sys.argv[6]

experimental_only_names = [
    "tcproutes.gateway.networking.k8s.io",
    "udproutes.gateway.networking.k8s.io",
    "xbackendtrafficpolicies.gateway.networking.x-k8s.io",
    "xmeshes.gateway.networking.x-k8s.io",
]


def crd_docs(text: str) -> list[tuple[str, str]]:
    docs: list[tuple[str, str]] = []
    for part in re.split(r"(?m)^---\s*$", text):
        block = part.strip()
        if not block or "kind: CustomResourceDefinition" not in block:
            continue
        match = re.search(r"(?m)^  name: \"?([^\"\n]+)\"?\s*$", block)
        if not match:
            raise SystemExit("CRD metadata.name was not found in upstream manifest block")
        name = match.group(1)
        docs.append((name, block.rstrip() + "\n"))
    return docs


def write_doc(path: Path, block: str) -> None:
    path.write_text("---\n" + block, encoding="utf-8")

standard_docs = crd_docs(standard_manifest.read_text(encoding="utf-8"))
experimental_docs = dict(crd_docs(experimental_manifest.read_text(encoding="utf-8")))

if not standard_docs:
    raise SystemExit("no standard Gateway API CRDs found")

missing = [name for name in experimental_only_names if name not in experimental_docs]
if missing:
    raise SystemExit(f"missing expected experimental Gateway API CRDs: {', '.join(missing)}")

standard_dir.mkdir(parents=True, exist_ok=True)
for old in standard_dir.glob("*.yaml"):
    old.unlink()
for name, block in sorted(standard_docs):
    write_doc(standard_dir / f"{name}.yaml", block)

standard_chart_text = standard_chart.read_text(encoding="utf-8")
standard_chart_text = re.sub(
    r"(?m)^appVersion: .*$",
    f"appVersion: {gateway_api_version.lstrip('v')}",
    standard_chart_text,
)
standard_chart.write_text(standard_chart_text, encoding="utf-8")

experimental_body = "".join("---\n" + experimental_docs[name] for name in experimental_only_names)
experimental_template.write_text(
    '{{- if and .Values.gatewayAPI.installCRDs (eq .Values.gatewayAPI.channel "experimental") }}\n'
    + experimental_body
    + "{{- end }}\n",
    encoding="utf-8",
)

print(
    f"Synced Gateway API {gateway_api_version}: "
    f"{len(standard_docs)} standard CRDs, {len(experimental_only_names)} experimental-only CRDs"
)
PY
