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

By default, component image tags are empty in `values.yaml`, so the chart uses `.Chart.AppVersion`. For stricter supply-chain control, pin image digests or immutable release tags in environment values, configure external secrets for TLS and admin authentication, and run the validation command before rollout:

```bash
helm lint charts/nantian-gw
helm template nantian-gw charts/nantian-gw --namespace nantian-gw
```

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

The chart vendors official Gateway API v1.5.1 CRDs and renders them from templates so values can control CRD installation:

```yaml
gatewayAPI:
  installCRDs: false
  channel: standard # standard | experimental
```

`installCRDs=true` renders Gateway API CRDs from this chart. `channel=standard` renders the official standard bundle. `channel=experimental` renders the official experimental bundle, including resources such as TCPRoute and UDPRoute.

`installCRDs=false` is the production default and renders no Gateway API CRDs. Use this when CRDs are managed by a platform team, GitOps controller, or a separate cluster bootstrap process. In that mode, install official CRDs before applying Gateway API resources:

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
    tag: ""
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

Use at least two replicas for availability. Keep leader election enabled when replicas are greater than one. Leave `tag` empty to use `.Chart.AppVersion`, or replace it with an immutable release tag or digest for production rollouts.

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

### Dataplane

The data plane serves gateway traffic and connects to the control plane.

Important production settings:

```yaml
dataplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/dataplane
    tag: ""
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

Use `sessionPersistence.existingSecret` or `sessionPersistence.sharedSecret` when multi-replica dataplanes need stable HMAC-backed session behavior. Prefer `existingSecret` in production so secret rotation is managed outside Helm values.

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
```

`networkPolicies.enabled=true` restricts control plane, data plane, and dashboard ingress. Keep it enabled in production and tune cluster-level NetworkPolicy behavior as needed.

`tests.enabled=true` renders a Helm test pod that checks health endpoints. Run it after install:

```bash
helm test nantian-gw --namespace nantian-gw
```

`certs.generate=true` creates chart-managed self-signed certificates and keeps/reuses the generated Secrets across upgrades. This is convenient for development, but production should normally use cert-manager or pre-created secrets:

```yaml
certs:
  generate: false
```

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

Pinned production images:

```yaml
controlplane:
  image:
    tag: v0.1.0
    pullPolicy: IfNotPresent
dataplane:
  image:
    tag: v0.1.0
    pullPolicy: IfNotPresent
dashboard:
  image:
    tag: v0.1.0
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

默认镜像 tag 在 `values.yaml` 中为空，因此会使用 `.Chart.AppVersion`。生产环境可以进一步固定镜像 digest 或不可变发布 tag；TLS、Admin API token 等敏感配置应使用外部 Secret；上线前运行：

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

`installCRDs=true` 表示由本 Chart 渲染 Gateway API CRD。`channel=standard` 渲染官方 standard bundle。`channel=experimental` 渲染官方 experimental bundle，其中包含 TCPRoute、UDPRoute 等实验性资源。

`installCRDs=false` 是生产默认值，表示本 Chart 不渲染 Gateway API CRD。平台团队统一管理 CRD、使用 GitOps 管理 CRD、或在集群初始化阶段单独安装 CRD 时，建议使用这个模式。此时应先安装官方 CRD：

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
    tag: ""
    pullPolicy: Always
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

生产建议至少两个副本，并在多副本时保持 leader election 开启。`tag` 为空时使用 `.Chart.AppVersion`，也可以在环境 values 中替换为不可变发布 tag 或 digest。

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

### 数据面

数据面负责处理网关流量，并连接控制面。

重要生产配置：

```yaml
dataplane:
  enabled: true
  replicas: 2
  image:
    repository: nantian-gw/dataplane
    tag: ""
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

多副本数据面需要稳定会话行为时，可使用 `sessionPersistence.existingSecret` 或 `sessionPersistence.sharedSecret`。生产环境优先使用 `existingSecret`，避免将密钥直接写入 Helm values。

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
```

`networkPolicies.enabled=true` 会限制控制面、数据面和 Dashboard 的入站流量。生产环境建议保持开启，并结合集群网络插件策略进行调整。

`tests.enabled=true` 会渲染 Helm test Pod，用于检查健康端点。安装后可运行：

```bash
helm test nantian-gw --namespace nantian-gw
```

`certs.generate=true` 会创建 Chart 管理的自签名证书，并在升级时保留/复用已生成的 Secret。它适合开发和快速验证，生产环境通常应使用 cert-manager 或预创建 Secret：

```yaml
certs:
  generate: false
```

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

固定生产镜像：

```yaml
controlplane:
  image:
    tag: v0.1.0
    pullPolicy: IfNotPresent
dataplane:
  image:
    tag: v0.1.0
    pullPolicy: IfNotPresent
dashboard:
  image:
    tag: v0.1.0
    pullPolicy: IfNotPresent
```
