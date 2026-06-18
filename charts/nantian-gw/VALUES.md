# Nantian Gateway Helm Values

This document explains the main `values.yaml` settings for the `nantian-gw` Helm chart. It is intentionally more detailed than inline YAML comments so production operators can decide which settings belong in cluster defaults, environment overlays, or release-specific values files.

本文档说明 `nantian-gw` Helm Chart 的主要 `values.yaml` 配置。相比 YAML 内联注释，这里提供更完整的生产环境说明，便于平台团队决定哪些配置应放入集群默认值、环境覆盖文件或具体发布的 values 文件中。

## English

### Production Default

The chart defaults to a standard production-oriented install:

```yaml
featureMode: standard
gatewayAPI:
  installCRDs: false
  channel: standard
controlplane:
  replicas: 2
dataplane:
  replicas: 2
networkPolicies:
  enabled: true
```

The default mode keeps experimental runtime features disabled, does not render cluster-scoped Gateway API CRDs, creates two control plane replicas, creates two data plane replicas, enables PodDisruptionBudgets when replicas are greater than one, and keeps NetworkPolicies enabled.

The base chart defaults use the `latest` tag for control plane, data plane, and dashboard images so a fresh install follows the currently published public images. The production preset pins the current published component images to immutable `sha-*` tags; replace those tags with your promoted release tags or digests during release promotion. Configure external secrets for TLS and admin authentication, and run the validation command before rollout:

```bash
helm lint charts/nantian-gw
helm template nantian-gw charts/nantian-gw --namespace nantian-gw
```

### Preset Values Files

The chart also ships with scenario overlays that are meant to be layered on top of the base defaults:

```bash
helm upgrade --install nantian-gw charts/nantian-gw \
  --namespace nantian-gw \
  -f charts/nantian-gw/values.yaml \
  -f charts/nantian-gw/values-production.yaml
```

- `values-dev.yaml`: local Kind or disposable cluster installs
- `values-staging.yaml`: shared test or pre-production validation
- `values-production.yaml`: explicit production baseline
- `values-ai-gateway.yaml`: experimental runtime plus AI gateway overlay

These preset files intentionally do not set environment-specific secrets, Ingress hosts, TLS issuers, or existing Secret names. The production preset sets immutable component image tags for the current validated image set.

这些预设文件用于覆盖基础默认值，而不是替代 `values.yaml`。建议使用 `-f values.yaml -f values-*.yaml` 的叠加方式。

- `values-dev.yaml`：本地 Kind 或一次性测试集群
- `values-staging.yaml`：联调或预发布环境
- `values-production.yaml`：生产环境基线
- `values-ai-gateway.yaml`：实验性运行时与 AI 网关场景

这些预设不会内置环境相关的 Secret、Ingress Host、TLS Issuer 或已有 Secret 名称。生产 preset 会内置当前验证过的不可变组件镜像 tag。

### Feature Modes

`featureMode` controls Nantian Gateway runtime feature gates, not CRD installation:

```yaml
featureMode: standard # standard | experimental
```

`standard` is the default and is intended for production. It forces `controlplane.config.features.enableExperimentalGateway` and `controlplane.config.features.enableAiGateway` to render as `false`.

`experimental` explicitly enables the experimental Gateway runtime integration point by rendering `enableExperimentalGateway: true`. AI Gateway remains independently controlled by `controlplane.config.features.enableAiGateway` and defaults to `false`.

Use experimental mode only for controlled tests or clusters that accept API and behavior changes:

```bash
helm upgrade --install nantian-gw charts/nantian-gw \
  --namespace nantian-gw \
  --set featureMode=experimental
```

### Gateway API CRDs

The chart vendors official Gateway API v1.5.1 CRDs:

```yaml
gatewayAPI:
  installCRDs: false
  channel: standard # standard | experimental
```

The chart now splits CRD handling by bundle type:

- `installCRDs=false` renders no Gateway API CRDs.
- `installCRDs=true, channel=standard` installs the standard bundle through Helm's `crds/` mechanism.
- `installCRDs=true, channel=experimental` installs the standard bundle through `crds/` and renders only the experimental-only CRDs from templates, including `TCPRoute`, `UDPRoute`, `xBackendTrafficPolicy`, and `xMesh`.

Helm `crds/` resources are installed before ordinary manifests, are not removed by `helm uninstall`, and are not managed like normal templated resources during upgrades.

`installCRDs=false` is the production default. Use it when CRDs are managed by a platform team, GitOps controller, or a separate cluster bootstrap process. In that mode, install official CRDs before applying Gateway API resources:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

For experimental Gateway API CRDs managed outside the chart:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

CRDs are cluster-scoped resources. In multi-tenant clusters, prefer `gatewayAPI.installCRDs=false` for application releases and manage Gateway API CRDs once at the platform layer.

### Global Settings

`global.imageRegistry` prepends a registry to component images. The default is `ghcr.io`.

```yaml
global:
  imageRegistry: ghcr.io
  imagePullSecrets: []
  commonLabels: {}
```

Use `global.imagePullSecrets` when pulling from a private registry:

```yaml
global:
  imagePullSecrets:
    - nantian-registry
```

Use `global.commonLabels` for organization-wide labels such as owner, environment, or cost center. These labels are added to chart resources and should remain stable because selectors must not change after installation.

### Namespace, GatewayClass, and RBAC

`namespace.create=true` creates `namespace.name`. If `namespace.create=false`, resources are installed into the Helm release namespace.

```yaml
namespace:
  create: true
  name: nantian-gw
```

`gatewayClass.enabled=true` creates a GatewayClass. The GatewayClass name is derived from `gatewayClass.controllerName`.

```yaml
gatewayClass:
  enabled: true
  controllerName: gateway.networking.k8s.io/nantian-gw
```

`rbac.create=true` creates ServiceAccounts, ClusterRole, and ClusterRoleBinding. Disable it only when your platform provides equivalent RBAC resources:

```yaml
rbac:
  create: false
```

### Controlplane

The control plane watches Kubernetes Gateway API resources, translates desired state, and serves gRPC/admin/metrics/health endpoints.

Important production settings:

```yaml
controlplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/nantian-controlplane
    tag: latest
    pullPolicy: Always
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  leaderElection:
    enabled: true
```

Use at least two replicas for availability. Keep leader election enabled when replicas are greater than one. The current default `tag` is `latest` so quick installs follow the current public image set. Production rollouts should override it with an immutable release tag or digest.

`controlplane.grpcTLS` controls xDS/gRPC server TLS secret mounting:

```yaml
controlplane:
  grpcTLS:
    enabled: true
    existingSecret: nantian-controlplane-grpc-tls
    requireClientCert: true
```

`controlplane.adminAuth` mounts an existing bearer token secret for the admin API:

```yaml
controlplane:
  adminAuth:
    bearerTokenFile: /etc/nantian-gw/admin-auth/token
    existingSecret: nantian-controlplane-admin-auth
    secretKey: token
```

`controlplane.config.dashboardApi.dataplaneAdminUrl` is empty by default. When empty, the chart computes the in-cluster dataplane admin Service URL from the rendered chart name and namespace, for example `http://nantian-gw-dataplane-admin.nantian-gw.svc.cluster.local:19080`. Set it explicitly only when the control plane must call a different dataplane admin endpoint:

```yaml
controlplane:
  config:
    dashboardApi:
      dataplaneAdminUrl: http://custom-dataplane-admin.nantian-gw.svc.cluster.local:19080
```

`controlplane.config.dashboard` controls the Dashboard-facing capability policy that the control plane publishes to the UI. By default, `controlplane.config.dashboard.enabled` follows the chart-level `dashboard.enabled` toggle, so disabling the Dashboard deployment also disables the published Dashboard capability policy unless you explicitly override it:

```yaml
dashboard:
  enabled: false
controlplane:
  config:
    dashboard:
      enabled: false
      capabilities:
        aiOverview: true
        aiServices: true
        aiTokenPolicies: true
        aiCost: true
        aiTraces: true
        aiUsage: true
        wasmPlugins: true
        chatbot: true
```

Use `controlplane.config.dashboard.enabled` only when you intentionally want the control plane to advertise a different Dashboard availability policy than the chart-level Dashboard workload toggle. The nested `capabilities.*` switches only affect UI exposure policy; they do not enable backend AI or experimental runtime features by themselves.

Example: deploy the Dashboard but hide Wasm and chatbot surfaces from operators:

```yaml
dashboard:
  enabled: true
controlplane:
  config:
    dashboard:
      capabilities:
        wasmPlugins: false
        chatbot: false
```

### Dataplane

The data plane serves gateway traffic and connects to the control plane.

Important production settings:

```yaml
dataplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/dataplane
    tag: latest
    pullPolicy: Always
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 2000m
      memory: 1Gi
```

The chart mounts an `emptyDir` access log volume by default:

```yaml
dataplane:
  accessLogVolume:
    enabled: true
    name: access-logs
    mountPath: /var/log/nantian-gw
    sizeLimit: 256Mi
```

Disable `accessLogVolume.enabled` only when you provide your own volume through `extraVolumes` and `extraVolumeMounts`.

Use `dataplane.xdsTLS` with an existing secret when gRPC TLS is enabled on the control plane:

```yaml
dataplane:
  xdsTLS:
    enabled: true
    existingSecret: nantian-grpc-client-tls
    domainName: nantian-gw-controlplane-grpc.nantian-gw.svc.cluster.local
```

The chart keeps `dataplane.config.nodeId` as a fallback, but Kubernetes installs should rely on the chart-managed `AEG_NODE_ID` environment variable sourced from Pod `metadata.name`. That gives each replica a unique runtime node identity even when the static fallback remains `dp-kubernetes`.

By default, the chart also creates and reuses a stable dataplane admin bearer token Secret so the latest dataplane image can safely bind `0.0.0.0:19080`. The chart wires:

- dataplane `adminAuth.bearerTokenFile` to `/etc/nantian-gw/admin-auth/token`
- controlplane `adminRuntime.dataplaneAggregation.bearerTokenFile` to `/etc/nantian-gw/dataplane-admin-auth/token`

Replace the generated Secret with your own token by setting `dataplane.adminAuth.existingSecret`. Use `dataplane.adminAuth.secretKey` when the token key inside that Secret is not `token`.

Use `sessionPersistence.existingSecret` or `sessionPersistence.sharedSecret` when multi-replica dataplanes need stable HMAC-backed session behavior. When either option is set, the chart mounts the Secret and writes `sessionPersistence.secretKeyFile` into the rendered dataplane `config.yaml` automatically. Prefer `existingSecret` in production so secret rotation is managed outside Helm values.

### Dashboard

The dashboard is enabled by default:

```yaml
dashboard:
  enabled: true
  replicas: 1
  authExistingSecret: ""
  authSecret: ""
```

For production, prefer `authExistingSecret` with a pre-created secret containing the `auth-secret` key. If neither `authExistingSecret` nor `authSecret` is set, the chart creates a kept secret and reuses it on upgrades.

Newer chart versions create a dedicated Dashboard ServiceAccount by default through `dashboard.serviceAccount`. The token is not mounted unless `dashboard.serviceAccount.automountServiceAccountToken=true`. If you need to keep using an existing principal, set `dashboard.serviceAccount.create=false` and `dashboard.serviceAccount.name=<existing-sa>`.

`dashboard.ingress.enabled=false` is the default. Enable it only when an ingress controller is installed:

```yaml
dashboard:
  ingress:
    enabled: true
    className: nginx
    host: dashboard.example.com
    tls:
      enabled: true
      secretName: dashboard-example-tls
    fromNamespaces:
      - ingress-nginx
```

When NetworkPolicies are enabled, `dashboard.ingress.fromNamespaces` must include the ingress controller namespace when that controller runs outside the Helm release namespace, so it can reach the dashboard Service.

### Autoscaling, Monitoring, Network Policy, Tests, and Certificates

`hpa.enabled` creates a dataplane HorizontalPodAutoscaler. Enable it when metrics-server or equivalent metrics are available:

```yaml
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilization: 70
  targetMemoryUtilization: 75
```

`serviceMonitor.enabled` renders Prometheus Operator ServiceMonitor/PodMonitor resources:

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
  fromNamespaces:
    - monitoring
```

When NetworkPolicies are enabled, `serviceMonitor.fromNamespaces` must include any Prometheus namespace outside the Helm release namespace that needs to scrape metrics. Dataplane metrics share the admin port, so only grant trusted monitoring namespaces.

`networkPolicies.enabled=true` restricts control plane, data plane, and dashboard ingress. Keep it enabled in production and tune cluster-level NetworkPolicy behavior as needed.

`tests.enabled=true` renders a Helm test pod that checks health endpoints. By default the hook uses `public.ecr.aws/docker/library/busybox:1.36.1`, and operators can override `tests.image.repository`, `tests.image.tag`, and `tests.image.pullPolicy` to point at an internal mirror or a different compatible image. The chart hook policy deletes the test pod before recreation and after both successful and failed runs, so repeated `helm test` or uninstall flows do not leave stale failed hook pods behind. Run it after install:

```bash
helm test nantian-gw --namespace nantian-gw
```

`certs.generate=true` creates chart-managed self-signed certificates and keeps/reuses the generated Secrets across upgrades. This is convenient for development, but production should normally use cert-manager or pre-created secrets:

```yaml
certs:
  generate: false
```

For production gRPC/xDS TLS, prefer cert-manager or pre-created Secrets. The chart can render cert-manager `Certificate` resources when cert-manager and an Issuer already exist:

```yaml
controlplane:
  grpcTLS:
    enabled: true
    requireClientCert: true
dataplane:
  xdsTLS:
    enabled: true
certs:
  certManager:
    enabled: true
    issuerRef:
      name: nantian-ca
      kind: ClusterIssuer
      group: cert-manager.io
```

Rendering cert-manager `Certificate` resources does not by itself enable runtime TLS; operators still need `controlplane.grpcTLS.enabled=true` and `dataplane.xdsTLS.enabled=true`. Enabling `certs.certManager.enabled=true` still changes the pod manifests by mounting the expected TLS Secret volumes into the control plane and data plane workloads.

`certs.generate=true` remains a development shortcut. Newly generated self-signed material defaults to a 365-day CA and 90-day server/client certificates.

### Production Examples

Platform-managed CRDs:

```yaml
gatewayAPI:
  installCRDs: false
  channel: standard
featureMode: standard
```

Chart-managed standard CRDs:

```yaml
gatewayAPI:
  installCRDs: true
  channel: standard
featureMode: standard
```

Experimental lab install:

```yaml
featureMode: experimental
gatewayAPI:
  installCRDs: true
  channel: experimental
```

Example immutable production image pinning:

```yaml
controlplane:
  image:
    tag: sha-<controlplane-commit>
    pullPolicy: IfNotPresent
dataplane:
  image:
    tag: sha-<dataplane-commit>
    pullPolicy: IfNotPresent
dashboard:
  image:
    tag: sha-<dashboard-commit>
    pullPolicy: IfNotPresent
```

## 中文

### 生产默认模式

Chart 默认采用面向生产的标准安装：

```yaml
featureMode: standard
gatewayAPI:
  installCRDs: false
  channel: standard
controlplane:
  replicas: 2
dataplane:
  replicas: 2
networkPolicies:
  enabled: true
```

默认模式会关闭实验性运行时能力，不渲染集群级 Gateway API CRD，创建两个控制面副本和两个数据面副本，副本数大于 1 时启用 PodDisruptionBudget，并默认启用 NetworkPolicy。

基础 chart 默认对 controlplane、dataplane 和 dashboard 都使用 `latest` tag，便于跟随当前公开发布的镜像快速安装。生产 preset 会将当前已发布组件镜像固定到不可变 `sha-*` tag；正式发布推广时应替换为已晋级的 release tag 或 digest。TLS、Admin API token 等敏感配置应使用外部 Secret；上线前运行：

```bash
helm lint charts/nantian-gw
helm template nantian-gw charts/nantian-gw --namespace nantian-gw
```

### 功能模式

`featureMode` 控制 Nantian Gateway 自身的运行时功能开关，不控制 CRD 安装：

```yaml
featureMode: standard # standard | experimental
```

`standard` 是默认生产模式，会将 `controlplane.config.features.enableExperimentalGateway` 和 `controlplane.config.features.enableAiGateway` 渲染为 `false`。

`experimental` 表示显式进入实验模式，会将 `enableExperimentalGateway` 渲染为 `true`。AI Gateway 仍由 `controlplane.config.features.enableAiGateway` 单独控制，默认仍为 `false`。

实验模式只建议用于可控测试环境，或明确接受 API 与行为变化的集群：

```bash
helm upgrade --install nantian-gw charts/nantian-gw \
  --namespace nantian-gw \
  --set featureMode=experimental
```

### Gateway API CRD

Chart 内置官方 Gateway API v1.5.1 CRD，并从模板渲染，因此可以通过 values 控制是否安装：

```yaml
gatewayAPI:
  installCRDs: false
  channel: standard # standard | experimental
```

本 Chart 现在按 CRD 类型拆分安装方式：

- `installCRDs=false` 不渲染任何 Gateway API CRD。
- `installCRDs=true, channel=standard` 通过 Helm 的 `crds/` 机制安装 standard bundle。
- `installCRDs=true, channel=experimental` 通过 `crds/` 安装 standard bundle，并仅通过模板额外渲染实验性增量 CRD，包括 `TCPRoute`、`UDPRoute`、`xBackendTrafficPolicy` 和 `xMesh`。

Helm `crds/` 资源会先于普通模板资源安装，不会在 `helm uninstall` 时自动删除，也不会像普通模板资源那样在升级时由 Helm 常规覆盖管理。

`installCRDs=false` 是生产默认值。平台团队统一管理 CRD、使用 GitOps 管理 CRD、或在集群初始化阶段单独安装 CRD 时，建议使用这个模式。此时应先安装官方 CRD：

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```

如果由平台层安装实验性 CRD：

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

CRD 是集群级资源。多租户集群中，应用发布通常不应反复管理 CRD，建议应用 Chart 设置 `gatewayAPI.installCRDs=false`，由平台层统一安装和升级。

### 全局设置

`global.imageRegistry` 会作为所有组件镜像的默认 registry，默认值为 `ghcr.io`。

```yaml
global:
  imageRegistry: ghcr.io
  imagePullSecrets: []
  commonLabels: {}
```

私有镜像仓库可配置 `global.imagePullSecrets`：

```yaml
global:
  imagePullSecrets:
    - nantian-registry
```

`global.commonLabels` 适合设置 owner、environment、cost-center 等组织级标签。由于部分标签可能参与 selector，生产环境中应保持稳定，避免升级时改变 selector。

### Namespace、GatewayClass 和 RBAC

`namespace.create=true` 会创建 `namespace.name`。如果设置为 `false`，资源会安装到 Helm release namespace。

```yaml
namespace:
  create: true
  name: nantian-gw
```

`gatewayClass.enabled=true` 会创建 GatewayClass。GatewayClass 名称由 `gatewayClass.controllerName` 派生。

```yaml
gatewayClass:
  enabled: true
  controllerName: gateway.networking.k8s.io/nantian-gw
```

`rbac.create=true` 会创建 ServiceAccount、ClusterRole 和 ClusterRoleBinding。只有在平台已经提供等价 RBAC 时才应关闭：

```yaml
rbac:
  create: false
```

### 控制面

控制面负责监听 Kubernetes Gateway API 资源、生成目标配置，并提供 gRPC、Admin、Metrics 和健康检查端点。

重要生产配置：

```yaml
controlplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/nantian-controlplane
    tag: latest
    pullPolicy: Always
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

生产建议至少两个副本，并在多副本时保持 leader election 开启。当前默认 `tag` 是 `latest`，便于快速安装时跟随当前公开镜像；生产环境应在 values 中替换为不可变发布 tag 或 digest。

`controlplane.grpcTLS` 控制 gRPC 服务端 TLS Secret 挂载：

```yaml
controlplane:
  grpcTLS:
    enabled: true
    existingSecret: nantian-controlplane-grpc-tls
    requireClientCert: true
```

`controlplane.adminAuth` 用于挂载 Admin API bearer token：

```yaml
controlplane:
  adminAuth:
    bearerTokenFile: /etc/nantian-gw/admin-auth/token
    existingSecret: nantian-controlplane-admin-auth
    secretKey: token
```

`controlplane.config.dashboardApi.dataplaneAdminUrl` 默认为空。为空时，Chart 会根据渲染后的 chart 名称和 namespace 自动计算集群内数据面 Admin Service 地址，例如 `http://nantian-gw-dataplane-admin.nantian-gw.svc.cluster.local:19080`。只有当控制面需要访问不同的数据面 Admin 端点时才需要显式设置：

```yaml
controlplane:
  config:
    dashboardApi:
      dataplaneAdminUrl: http://custom-dataplane-admin.nantian-gw.svc.cluster.local:19080
```

`controlplane.config.dashboard` 用于控制控制面向 Dashboard 发布的能力策略。默认情况下，`controlplane.config.dashboard.enabled` 会跟随 chart 级别的 `dashboard.enabled` 开关，因此当你关闭 Dashboard 工作负载时，控制面默认也会同步发布 `dashboard.enabled=false`，除非你显式覆盖：

```yaml
dashboard:
  enabled: false
controlplane:
  config:
    dashboard:
      enabled: false
      capabilities:
        aiOverview: true
        aiServices: true
        aiTokenPolicies: true
        aiCost: true
        aiTraces: true
        aiUsage: true
        wasmPlugins: true
        chatbot: true
```

只有在你明确希望“Dashboard 工作负载是否部署”和“控制面向 UI 暴露的 Dashboard 可用性策略”不同步时，才需要单独设置 `controlplane.config.dashboard.enabled`。其中 `capabilities.*` 只控制 UI 暴露策略，不会自行开启后端 AI 或实验性运行时能力。

示例：部署 Dashboard，但对运维人员隐藏 Wasm 和 chatbot 功能入口：

```yaml
dashboard:
  enabled: true
controlplane:
  config:
    dashboard:
      capabilities:
        wasmPlugins: false
        chatbot: false
```

### 数据面

数据面负责处理网关流量，并连接控制面。

重要生产配置：

```yaml
dataplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/dataplane
    tag: latest
    pullPolicy: Always
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 2000m
      memory: 1Gi
```

默认会挂载 `emptyDir` 作为访问日志目录：

```yaml
dataplane:
  accessLogVolume:
    enabled: true
    name: access-logs
    mountPath: /var/log/nantian-gw
    sizeLimit: 256Mi
```

只有在通过 `extraVolumes` 和 `extraVolumeMounts` 提供自定义日志卷时，才建议关闭 `accessLogVolume.enabled`。

控制面开启 gRPC TLS 时，数据面应配置 `dataplane.xdsTLS`：

```yaml
dataplane:
  xdsTLS:
    enabled: true
    existingSecret: nantian-grpc-client-tls
    domainName: nantian-gw-controlplane-grpc.nantian-gw.svc.cluster.local
```

Chart 会保留 `dataplane.config.nodeId` 作为兜底值，但在 Kubernetes 场景下应以 Chart 自动注入、来源于 Pod `metadata.name` 的 `AEG_NODE_ID` 为准，这样即使静态兜底值仍是 `dp-kubernetes`，每个副本也会获得唯一的运行时节点身份。

默认情况下，Chart 还会创建并复用一个稳定的数据面 Admin bearer token Secret，以满足最新 dataplane 镜像对 `0.0.0.0:19080` 安全绑定的要求。Chart 会自动接线：

- 数据面 `adminAuth.bearerTokenFile` 到 `/etc/nantian-gw/admin-auth/token`
- 控制面 `adminRuntime.dataplaneAggregation.bearerTokenFile` 到 `/etc/nantian-gw/dataplane-admin-auth/token`

如果你希望改用自管 token Secret，请设置 `dataplane.adminAuth.existingSecret`。当 Secret 内的 token key 不是默认的 `token` 时，再同时设置 `dataplane.adminAuth.secretKey`。

多副本数据面需要稳定会话行为时，可使用 `sessionPersistence.existingSecret` 或 `sessionPersistence.sharedSecret`。设置任一方式后，Chart 会挂载对应 Secret，并自动把 `sessionPersistence.secretKeyFile` 写入渲染后的 dataplane `config.yaml`。生产环境优先使用 `existingSecret`，避免将密钥直接写入 Helm values。

### Dashboard

Dashboard 默认启用：

```yaml
dashboard:
  enabled: true
  replicas: 1
  authExistingSecret: ""
  authSecret: ""
```

生产环境建议使用 `authExistingSecret`，并预先创建包含 `auth-secret` key 的 Secret。如果 `authExistingSecret` 和 `authSecret` 都为空，Chart 会创建带 keep 策略的 Secret，并在升级时复用。

较新的 chart 版本默认通过 `dashboard.serviceAccount` 为 Dashboard 创建独立的 ServiceAccount。除非设置 `dashboard.serviceAccount.automountServiceAccountToken=true`，否则不会挂载 Kubernetes API token。如果仍需沿用现有身份，可设置 `dashboard.serviceAccount.create=false` 和 `dashboard.serviceAccount.name=<existing-sa>`。

`dashboard.ingress.enabled=false` 是默认值。只有在集群已经安装 Ingress Controller 时才启用：

```yaml
dashboard:
  ingress:
    enabled: true
    className: nginx
    host: dashboard.example.com
    tls:
      enabled: true
      secretName: dashboard-example-tls
    fromNamespaces:
      - ingress-nginx
```

启用 NetworkPolicy 时，如果 Ingress Controller 运行在 Helm release namespace 之外，`dashboard.ingress.fromNamespaces` 必须包含该 Ingress Controller 所在命名空间，Ingress Controller 才能访问 Dashboard Service。

### 自动扩缩容、监控、网络策略、测试和证书

`hpa.enabled` 会为数据面创建 HorizontalPodAutoscaler。集群具备 metrics-server 或等价指标能力时可开启：

```yaml
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilization: 70
  targetMemoryUtilization: 75
```

`serviceMonitor.enabled` 会渲染 Prometheus Operator 的 ServiceMonitor/PodMonitor：

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
  fromNamespaces:
    - monitoring
```

启用 NetworkPolicy 时，如果 Prometheus 运行在 Helm release namespace 之外，`serviceMonitor.fromNamespaces` 必须包含 Prometheus 所在命名空间才能抓取 metrics。dataplane metrics 与 admin 端口共用同一个端口，因此只应放行可信监控命名空间。

`networkPolicies.enabled=true` 会限制控制面、数据面和 Dashboard 的入站流量。生产环境建议保持开启，并结合集群网络插件策略进行调整。

`tests.enabled=true` 会渲染 Helm test Pod，用于检查健康端点。默认镜像为 `public.ecr.aws/docker/library/busybox:1.36.1`，运维人员仍可通过 `tests.image.repository`、`tests.image.tag` 和 `tests.image.pullPolicy` 覆盖到内部镜像仓库或其他兼容镜像。Chart 的 hook 策略会在重新创建前删除旧 Pod，并在测试成功或失败后自动清理测试 Pod，因此重复执行 `helm test` 或卸载时不会遗留失败的 hook Pod。安装后可运行：

```bash
helm test nantian-gw --namespace nantian-gw
```

`certs.generate=true` 会创建 Chart 管理的自签名证书，并在升级时保留/复用已生成的 Secret。它适合开发和快速验证，生产环境通常应使用 cert-manager 或预创建 Secret：

```yaml
certs:
  generate: false
```

生产环境的 gRPC/xDS TLS 建议使用 cert-manager 或预先创建的 Secret。集群已经安装 cert-manager 且存在 Issuer 时，chart 可以渲染 cert-manager `Certificate` 资源：

```yaml
controlplane:
  grpcTLS:
    enabled: true
    requireClientCert: true
dataplane:
  xdsTLS:
    enabled: true
certs:
  certManager:
    enabled: true
    issuerRef:
      name: nantian-ca
      kind: ClusterIssuer
      group: cert-manager.io
```

仅渲染 cert-manager `Certificate` 资源并不会自动启用运行时 TLS；仍需显式设置 `controlplane.grpcTLS.enabled=true` 和 `dataplane.xdsTLS.enabled=true`。但启用 `certs.certManager.enabled=true` 仍会修改 Pod 清单，为控制面和数据面工作负载挂载约定的 TLS Secret 卷。

`certs.generate=true` 仍然只作为开发环境快捷方式。新生成的自签名证书默认使用 365 天 CA 和 90 天 server/client 证书。

### 生产示例

平台统一管理 CRD：

```yaml
gatewayAPI:
  installCRDs: false
  channel: standard
featureMode: standard
```

由 Chart 管理 standard CRD（开发或单集群快速安装）：

```yaml
gatewayAPI:
  installCRDs: true
  channel: standard
featureMode: standard
```

实验环境：

```yaml
featureMode: experimental
gatewayAPI:
  installCRDs: true
  channel: experimental
```

固定生产镜像示例：

```yaml
controlplane:
  image:
    tag: sha-<controlplane-commit>
    pullPolicy: IfNotPresent
dataplane:
  image:
    tag: sha-<dataplane-commit>
    pullPolicy: IfNotPresent
dashboard:
  image:
    tag: sha-<dashboard-commit>
    pullPolicy: IfNotPresent
```
