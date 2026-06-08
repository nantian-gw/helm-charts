# Nantian Gateway Helm Charts

Helm charts for deploying [Nantian Gateway](https://github.com/nantian-gw/gateway).

## Charts

| Chart | Description |
|---|---|
| [nantian-gw](./charts/nantian-gw) | Full Nantian Gateway stack — controlplane, dataplane, and dashboard |

## Usage

```bash
helm repo add nantian-gw https://chart.nantian.dev
helm install nantian-gw nantian-gw/nantian-gw --namespace nantian-gw --create-namespace
```

## Development

### Cutting a release

Push a version tag to trigger the release workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The GitHub Actions workflow will:
1. Package the chart → `nantian-gw-{version}.tgz`
2. Create a GitHub Release with the `.tgz` attached
3. Update `index.yaml` pointing to the release artifact
4. Cloudflare Pages picks up the new `index.yaml` and deploys to `chart.nantian.dev`