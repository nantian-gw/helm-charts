# Nantian Gateway Helm Charts

Helm charts for deploying [Nantian Gateway](https://github.com/nantian-gw/gateway) — Kubernetes Gateway API with a built-in AI gateway.

## Charts

| Chart | Description |
|---|---|
| [nantian-gw](./charts/nantian-gw) | Full Nantian Gateway stack — controlplane, dataplane, and dashboard |

Detailed values documentation is available in [charts/nantian-gw/VALUES.md](./charts/nantian-gw/VALUES.md).

## Usage

```bash
helm repo add nantian-gw https://chart.nantian.dev
helm install nantian-gw nantian-gw/nantian-gw --namespace nantian-gw --create-namespace
```

## Development

### Syncing Gateway API CRDs

The chart vendors Gateway API CRDs from a pinned upstream release. Do not edit those CRD YAML files by hand; regenerate them and verify the result:

```bash
GATEWAY_API_VERSION=v1.5.1 bash scripts/sync-gateway-api-crds.sh
bash scripts/verify-gateway-api-crds.sh
```

`verify-gateway-api-crds.sh` is also wired into chart CI, snapshot publishing, and release publishing so stale CRD bundles fail before packaging.

### Cutting a release

Push a version tag to trigger the release workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The GitHub Actions workflow will:
1. Package the chart → `nantian-gw-{version}.tgz`
2. Update `index.yaml` on the `gh-pages` branch
3. Publish the stable chart through GitHub Pages at `https://chart.nantian.dev`

### Snapshot charts

Every push to `main` runs chart validation and publishes one immutable snapshot chart version for each commit included in that push:

```text
<Chart.yaml version>-<git short SHA>
```

For example, chart version `0.2.3` at commit `abc1234` is published as `0.2.3-abc1234`. Helm treats these versions as prereleases, so use `helm search repo nantian-gw --devel` when you want to list snapshot charts. Stable chart versions are still created from `v*` tags.
