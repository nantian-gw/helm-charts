# Secret Management

This document covers recommended approaches for managing Secrets in GitOps workflows
with the Nantian Gateway Helm chart.

## Option 1: Sealed Secrets

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) encrypt Kubernetes Secrets
into `SealedSecret` resources that are safe to commit to Git. The cluster-side controller
decrypts them into standard Secrets at reconciliation time.

### Creating a Sealed Secret

```bash
# 1. Create a plain Secret (do NOT commit this)
kubectl create secret generic my-tls-secret \
  --from-file=tls.crt=cert.pem \
  --from-file=tls.key=key.pem \
  --from-file=ca.crt=ca.pem \
  --dry-run=client -o yaml > secret.yaml

# 2. Seal it with kubeseal (the output is safe to commit)
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# 3. Delete the plain secret.yaml — never commit it
rm secret.yaml
```

### Referencing a Sealed Secret in values.yaml

```yaml
# dataplane xDS mTLS — certs must NOT be auto-generated
certs:
  generate: false

controlplane:
  grpcTLS:
    enabled: true
    existingSecret: "my-sealed-tls-secret"

dataplane:
  xdsTLS:
    enabled: true
    existingSecret: "my-sealed-tls-secret"
```

The `existingSecret` fields accept the name of your `SealedSecret` resource.
The controller decrypts it into a Kubernetes Secret of the same name, which the
chart then mounts.

### Sealed Secret Structure

The Secret backing the `existingSecret` for gRPC/xDS mTLS must contain:

| Key      | Purpose                     |
|----------|-----------------------------|
| `tls.crt`| Server / client certificate |
| `tls.key`| Private key                 |
| `ca.crt` | CA certificate for mTLS     |

### Rotating Sealed Secrets

```bash
# 1. Generate new cert material
# 2. Create a new plain Secret, seal it
kubeseal --format yaml < new-secret.yaml > new-sealed-secret.yaml

# 3. Update the SealedSecret in your Git repo
# 4. Apply the new SealedSecret
kubectl apply -f new-sealed-secret.yaml

# 5. Trigger a rollout restart of the affected component
kubectl rollout restart deployment -n nantian-gw -l app.kubernetes.io/component=controlplane
kubectl rollout restart daemonset -n nantian-gw -l app.kubernetes.io/component=dataplane
```

> **Note:** The Sealed Secrets controller does not detect content changes to
> SealedSecret resources automatically after the initial creation. To update an
> existing SealedSecret, delete it first or apply `kubeseal --merge-into` to
> patch the existing resource with the new encrypted data.

---

## Option 2: External Secrets Operator

[External Secrets Operator](https://external-secrets.io/) (ESO) synchronises
secrets from external providers (AWS Secrets Manager, GCP Secret Manager, Azure
Key Vault, HashiCorp Vault, etc.) into Kubernetes Secrets.

### Prerequisites

- External Secrets Operator installed in the cluster
- A `SecretStore` or `ClusterSecretStore` configured for your provider
- Secrets populated in your external secret manager

### Example: AWS Secrets Manager

Create a `ClusterSecretStore` (one-time setup per cluster):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-service-account
            namespace: external-secrets
```

Create an `ExternalSecret` that syncs the TLS material:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nantian-gw-tls
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: nantian-gw-tls
  data:
    - secretKey: tls.crt
      remoteRef:
        key: /nantian-gw/tls-cert
        property: certificate
    - secretKey: tls.key
      remoteRef:
        key: /nantian-gw/tls-key
        property: private_key
    - secretKey: ca.crt
      remoteRef:
        key: /nantian-gw/tls-ca
        property: certificate
```

Reference it in values:

```yaml
certs:
  generate: false

controlplane:
  grpcTLS:
    enabled: true
    existingSecret: "nantian-gw-tls"

dataplane:
  xdsTLS:
    enabled: true
    existingSecret: "nantian-gw-tls"
```

### Example: GCP Secret Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secretmanager
spec:
  provider:
    gcpsm:
      projectID: my-gcp-project
      auth:
        workloadIdentity:
          clusterLocation: us-central1-a
          clusterName: my-cluster
          serviceAccountRef:
            name: eso-service-account
            namespace: external-secrets
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nantian-gw-tls
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secretmanager
    kind: ClusterSecretStore
  target:
    name: nantian-gw-tls
  data:
    - secretKey: tls.crt
      remoteRef:
        key: nantian-gw-tls-cert
    - secretKey: tls.key
      remoteRef:
        key: nantian-gw-tls-key
    - secretKey: ca.crt
      remoteRef:
        key: nantian-gw-tls-ca
```

### Example: Multi-Component Secrets

You can sync secrets for multiple components from a single `ExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nantian-gw-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: nantian-gw-secrets
  data:
    # gRPC/xDS mTLS certs
    - secretKey: tls.crt
      remoteRef:
        key: /nantian-gw/tls-cert
        property: certificate
    - secretKey: tls.key
      remoteRef:
        key: /nantian-gw/tls-key
        property: private_key
    - secretKey: ca.crt
      remoteRef:
        key: /nantian-gw/tls-ca
        property: certificate
    # Controlplane admin bearer token
    - secretKey: admin-token
      remoteRef:
        key: /nantian-gw/admin-token
    # Dashboard AUTH_SECRET
    - secretKey: auth-secret
      remoteRef:
        key: /nantian-gw/auth-secret
```

Then in values:

```yaml
certs:
  generate: false

controlplane:
  grpcTLS:
    existingSecret: "nantian-gw-secrets"

dataplane:
  xdsTLS:
    existingSecret: "nantian-gw-secrets"

controlplane:
  adminAuth:
    existingSecret: "nantian-gw-secrets"
    secretKey: "admin-token"

dashboard:
  authExistingSecret: "nantian-gw-secrets"
```

---

## Option 3: cert-manager

[cert-manager](https://cert-manager.io/) can be used with its `Certificate`
resource to provision TLS certificates from an Issuer and store the result in
a Kubernetes Secret referenced by the chart.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nantian-gw-grpc-tls
spec:
  secretName: nantian-gw-grpc-tls
  duration: 2160h   # 90d
  renewBefore: 360h # 15d
  subject:
    organizations:
      - nantian-gw
  privateKey:
    algorithm: ECDSA
    size: 256
  usages:
    - server auth
    - client auth
  dnsNames:
    - nantian-gw-controlplane.nantian-gw.svc
  issuerRef:
    name: my-ca-issuer
    kind: Issuer
```

Reference in values:

```yaml
certs:
  generate: false

controlplane:
  grpcTLS:
    existingSecret: "nantian-gw-grpc-tls"
```

---

## Secret Rotation Best Practices

### Automated Rotation with ESO

External Secrets Operator refreshes Secrets at `refreshInterval`. The Pods still
need a restart to pick up the new cert material. Consider:

- **Using `stakater/Reloader`** to detect Secret changes and trigger rolling
  restarts automatically via annotations.
- **Using a CronJob** that checks cert expiry and performs `kubectl rollout restart`
  when needed.

### Manual Rotation Checklist

1. **Generate** new cert material and update the external secret store (or Sealed
   Secret in Git).
2. **Apply** the updated Secret (or wait for ESO refresh).
3. **Verify** the new Secret data: `kubectl get secret <name> -o yaml`.
4. **Restart** affected components:
   ```bash
   kubectl rollout restart deployment -n nantian-gw nantian-gw-controlplane
   kubectl rollout restart daemonset -n nantian-gw nantian-gw-dataplane
   kubectl rollout restart deployment -n nantian-gw nantian-gw-dashboard
   ```
5. **Monitor** for successful rollout and connectivity:
   ```bash
   kubectl get pods -n nantian-gw -w
   kubectl logs -n nantian-gw -l app.kubernetes.io/component=controlplane --tail=20
   ```

### Pre-Rotation Grace Period

For short-lived certs (default 90d for server), schedule rotation at least **15
days before expiry**. The `renewBefore` field in cert-manager and the
`refreshInterval` in ESO provide guardrails — set them conservatively.

### Never Commit Plain Secrets

| ✓ Do                            | ✗ Don't                             |
|---------------------------------|-------------------------------------|
| Commit `SealedSecret` YAML     | Commit plain `Secret` YAML          |
| Reference `existingSecret` name | Embed sensitive values in `values.yaml` |
| Use `external-secrets` CRDs     | Store tokens in ConfigMaps          |
| Rotate on a schedule            | Rotate only when something breaks   |
