{{/*
Expand the name of the chart.
*/}}
{{- define "nantian-gw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nantian-gw.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nantian-gw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nantian-gw.labels" -}}
helm.sh/chart: {{ include "nantian-gw.chart" . }}
{{ include "nantian-gw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nantian-gw
{{- with .Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nantian-gw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nantian-gw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Controlplane labels
*/}}
{{- define "nantian-gw.controlplane.labels" -}}
{{ include "nantian-gw.labels" . }}
app.kubernetes.io/component: controlplane
app: {{ include "nantian-gw.name" . }}-controlplane
{{- end }}

{{/*
Controlplane selector labels
*/}}
{{- define "nantian-gw.controlplane.selectorLabels" -}}
{{ include "nantian-gw.selectorLabels" . }}
app: {{ include "nantian-gw.name" . }}-controlplane
{{- end }}

{{/*
Dataplane labels
*/}}
{{- define "nantian-gw.dataplane.labels" -}}
{{ include "nantian-gw.labels" . }}
app.kubernetes.io/component: dataplane
app: {{ include "nantian-gw.name" . }}-dataplane
{{- end }}

{{/*
Dataplane selector labels
*/}}
{{- define "nantian-gw.dataplane.selectorLabels" -}}
{{ include "nantian-gw.selectorLabels" . }}
app: {{ include "nantian-gw.name" . }}-dataplane
{{- end }}

{{/*
Dashboard labels
*/}}
{{- define "nantian-gw.dashboard.labels" -}}
{{ include "nantian-gw.labels" . }}
app.kubernetes.io/component: dashboard
app: {{ include "nantian-gw.name" . }}-dashboard
{{- end }}

{{/*
Dashboard selector labels
*/}}
{{- define "nantian-gw.dashboard.selectorLabels" -}}
{{ include "nantian-gw.selectorLabels" . }}
app: {{ include "nantian-gw.name" . }}-dashboard
{{- end }}

{{/*
Dashboard service account name.
*/}}
{{- define "nantian-gw.dashboard.serviceAccountName" -}}
{{- if .Values.dashboard.serviceAccount.name -}}
{{- .Values.dashboard.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-dashboard" (include "nantian-gw.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Controlplane image
*/}}
{{- define "nantian-gw.controlplane.image" -}}
{{- $registry := .Values.controlplane.image.registry -}}
{{- if not $registry -}}
{{- $registry = .Values.global.imageRegistry -}}
{{- end -}}
{{- $repository := .Values.controlplane.image.repository -}}
{{- $tag := .Values.controlplane.image.tag | default .Chart.AppVersion -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Dataplane image
*/}}
{{- define "nantian-gw.dataplane.image" -}}
{{- $registry := .Values.dataplane.image.registry -}}
{{- if not $registry -}}
{{- $registry = .Values.global.imageRegistry -}}
{{- end -}}
{{- $repository := .Values.dataplane.image.repository -}}
{{- $tag := .Values.dataplane.image.tag | default .Chart.AppVersion -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Dashboard image
*/}}
{{- define "nantian-gw.dashboard.image" -}}
{{- $registry := .Values.dashboard.image.registry -}}
{{- if not $registry -}}
{{- $registry = .Values.global.imageRegistry -}}
{{- end -}}
{{- $repository := .Values.dashboard.image.repository -}}
{{- $tag := .Values.dashboard.image.tag | default .Chart.AppVersion -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Release namespace
*/}}
{{- define "nantian-gw.namespace" -}}
{{- if .Values.namespace.create }}
{{- .Values.namespace.name }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Image pull secrets
*/}}
{{- define "nantian-gw.imagePullSecrets" -}}
{{- $secrets := list -}}
{{- range .Values.global.imagePullSecrets }}
{{- $secrets = append $secrets (dict "name" .) }}
{{- end }}
{{- if $secrets }}
imagePullSecrets:
{{ toYaml $secrets }}
{{- end }}
{{- end }}

{{/*
Security context defaults
*/}}
{{- define "nantian-gw.podSecurityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{/*
Dataplane pod security context.
Low-port binding is handled by NET_BIND_SERVICE capability.
*/}}
{{- define "nantian-gw.dataplanePodSecurityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
  {{- if not .Values.dataplane.hostNetwork }}
  sysctls:
    - name: net.ipv4.ip_unprivileged_port_start
      value: "0"
  {{- end }}
{{- end }}

{{/*
Container security context
*/}}
{{- define "nantian-gw.containerSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
{{- end }}

{{/*
Dataplane container security context
*/}}
{{- define "nantian-gw.dataplaneContainerSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
{{- end }}

{{/*
Returns whether dataplane admin auth should be sourced from a Secret mount.
Inline bearerToken config disables secret-based defaulting.
*/}}
{{- define "nantian-gw.dataplaneAdminAuthUsesSecret" -}}
{{- $cfg := default (dict) .Values.dataplane.config -}}
{{- $adminAuth := default (dict) (get $cfg "admin_auth") -}}
{{- $inlineToken := trim (default "" (get $adminAuth "bearer_token")) -}}
{{- if and .Values.dataplane.enabled (not $inlineToken) -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Resolve the dataplane admin auth Secret name.
*/}}
{{- define "nantian-gw.dataplaneAdminAuthSecretName" -}}
{{- if .Values.dataplane.adminAuth.existingSecret -}}
{{- .Values.dataplane.adminAuth.existingSecret -}}
{{- else -}}
{{- printf "%s-dataplane-admin-auth" (include "nantian-gw.name" .) -}}
{{- end -}}
{{- end }}

{{/*
Resolve the dataplane admin auth file path inside the dataplane container.
*/}}
{{- define "nantian-gw.dataplaneAdminAuthFilePath" -}}
{{- $cfg := default (dict) .Values.dataplane.config -}}
{{- $adminAuth := default (dict) (get $cfg "admin_auth") -}}
{{- $configPath := trim (default "" (get $adminAuth "bearer_token_file")) -}}
{{- $chartPath := trim (default "" .Values.dataplane.adminAuth.bearerTokenFile) -}}
{{- if $configPath -}}
{{- $configPath -}}
{{- else if $chartPath -}}
{{- $chartPath -}}
{{- else -}}
{{- printf "/etc/nantian-gw/admin-auth/%s" .Values.dataplane.adminAuth.secretKey -}}
{{- end -}}
{{- end }}

{{/*
Resolve the dataplane session-persistence Secret file path inside the dataplane container.
*/}}
{{- define "nantian-gw.dataplaneSessionPersistenceFilePath" -}}
{{- printf "/etc/nantian-gw/session-persistence/%s" .Values.dataplane.sessionPersistence.secretKey -}}
{{- end }}

{{/*
Resolve the session persistence shared secret value.
1. Use an explicit existingSecret reference
2. Use an explicit sharedSecret value
3. Reuse an existing auto-generated Secret
4. Otherwise, generate a random value on first install
*/}}
{{- define "nantian-gw.session-persistence-secret" -}}
{{- if .Values.dataplane.sessionPersistence.sharedSecret -}}
{{- .Values.dataplane.sessionPersistence.sharedSecret -}}
{{- else if not .Values.dataplane.sessionPersistence.existingSecret -}}
{{- $ns := include "nantian-gw.namespace" . -}}
{{- $secretName := printf "%s-dataplane-session-persistence" (include "nantian-gw.name" .) -}}
{{- $secret := lookup "v1" "Secret" $ns $secretName -}}
{{- if and $secret (index $secret.data (.Values.dataplane.sessionPersistence.secretKey)) -}}
{{- index $secret.data .Values.dataplane.sessionPersistence.secretKey | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end }}

{{/*
Resolve the dataplane admin auth file path inside the controlplane container for dataplane aggregation.
Only used when the chart is supplying the bearer token Secret.
*/}}
{{- define "nantian-gw.controlplaneDataplaneAdminAuthFilePath" -}}
{{- $cfg := default (dict) .Values.controlplane.config -}}
{{- $adminRuntime := default (dict) (get $cfg "adminRuntime") -}}
{{- $dataplaneAggregation := default (dict) (get $adminRuntime "dataplaneAggregation") -}}
{{- $configuredPath := trim (default "" (get $dataplaneAggregation "bearer_token_file")) -}}
{{- if $configuredPath -}}
{{- $configuredPath -}}
{{- else -}}
{{- printf "/etc/nantian-gw/dataplane-admin-auth/%s" .Values.dataplane.adminAuth.secretKey -}}
{{- end -}}
{{- end }}

{{/*
Returns whether the controlplane should auto-mount the dataplane admin auth Secret.
*/}}
{{- define "nantian-gw.controlplaneDataplaneAdminAuthNeedsMount" -}}
{{- $cfg := default (dict) .Values.controlplane.config -}}
{{- $adminRuntime := default (dict) (get $cfg "adminRuntime") -}}
{{- $dataplaneAggregation := default (dict) (get $adminRuntime "dataplaneAggregation") -}}
{{- $configuredPath := trim (default "" (get $dataplaneAggregation "bearer_token_file")) -}}
{{- if and .Values.controlplane.enabled .Values.dataplane.enabled (eq (include "nantian-gw.dataplaneAdminAuthUsesSecret" .) "true") (not $configuredPath) -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Controlplane config as YAML
*/}}
{{- define "nantian-gw.controlplane.configYaml" -}}
{{- $cfg := deepCopy .Values.controlplane.config -}}
{{- /* controllerName is the single source of truth at gatewayClass.controllerName */ -}}
{{- $_ := set $cfg "controllerName" .Values.gatewayClass.controllerName -}}
{{- $dashboardApi := default (dict) $cfg.dashboardApi -}}
{{- if not (get $dashboardApi "dataplaneAdminUrl") -}}
{{- $_ := set $dashboardApi "dataplaneAdminUrl" (printf "http://%s-dataplane-admin.%s.svc.cluster.local:19080" (include "nantian-gw.name" .) (include "nantian-gw.namespace" .)) -}}
{{- $_ := set $cfg "dashboardApi" $dashboardApi -}}
{{- end -}}
{{- $adminRuntime := default (dict) $cfg.adminRuntime -}}
{{- if .Values.dataplane.enabled -}}
{{- $dataplaneAggregation := default (dict) (get $adminRuntime "dataplaneAggregation") -}}
{{- if not (get $dataplaneAggregation "serviceName") -}}
{{- $_ := set $dataplaneAggregation "serviceName" (printf "%s-dataplane-admin" (include "nantian-gw.name" .)) -}}
{{- end -}}
{{- if not (get $dataplaneAggregation "namespace") -}}
{{- $_ := set $dataplaneAggregation "namespace" (include "nantian-gw.namespace" .) -}}
{{- end -}}
{{- if not (get $dataplaneAggregation "portName") -}}
{{- $_ := set $dataplaneAggregation "portName" "admin" -}}
{{- end -}}
{{- if not (get $dataplaneAggregation "timeout") -}}
{{- $_ := set $dataplaneAggregation "timeout" "2s" -}}
{{- end -}}
{{- if and (eq (include "nantian-gw.controlplaneDataplaneAdminAuthNeedsMount" .) "true") (not (get $dataplaneAggregation "bearer_token_file")) -}}
{{- $_ := set $dataplaneAggregation "bearer_token_file" (include "nantian-gw.controlplaneDataplaneAdminAuthFilePath" .) -}}
{{- end -}}
{{- $_ := set $adminRuntime "dataplaneAggregation" $dataplaneAggregation -}}
{{- $_ := set $cfg "adminRuntime" $adminRuntime -}}
{{- end -}}
{{- $configuredDashboard := default (dict) $cfg.dashboard -}}
{{- if not (hasKey $configuredDashboard "enabled") -}}
{{- $_ := set $configuredDashboard "enabled" .Values.dashboard.enabled -}}
{{- end -}}
{{- $defaultDashboardCaps := dict "aiOverview" true "aiServices" true "aiTokenPolicies" true "aiCost" true "aiTraces" true "aiUsage" true "wasmPlugins" true "chatbot" true -}}
{{- $configuredDashboardCaps := default (dict) (get $configuredDashboard "capabilities") -}}
{{- $_ := set $configuredDashboard "capabilities" (mergeOverwrite (deepCopy $defaultDashboardCaps) $configuredDashboardCaps) -}}
{{- $_ := set $cfg "dashboard" $configuredDashboard -}}
{{- $configuredFeatures := default (dict) $cfg.features -}}
{{- $experimentalGatewayEnabled := eq .Values.featureMode "experimental" -}}
{{- $aiGatewayEnabled := and $experimentalGatewayEnabled (default false (get $configuredFeatures "enableAiGateway")) -}}
{{- $features := mergeOverwrite (deepCopy $configuredFeatures) (dict "enableExperimentalGateway" $experimentalGatewayEnabled "enableAiGateway" $aiGatewayEnabled) -}}
{{- $_ := set $cfg "features" $features -}}
{{- $grpcTLS := default (dict) $cfg.grpcTLS -}}
{{- if .Values.controlplane.grpcTLS.enabled -}}
{{- $_ := set $grpcTLS "enabled" true -}}
{{- if not (get $grpcTLS "certPath") -}}
{{- $_ := set $grpcTLS "certPath" "/etc/nantian-gw/grpc-tls/tls.crt" -}}
{{- end -}}
{{- if not (get $grpcTLS "keyPath") -}}
{{- $_ := set $grpcTLS "keyPath" "/etc/nantian-gw/grpc-tls/tls.key" -}}
{{- end -}}
{{- if not (get $grpcTLS "clientCAPath") -}}
{{- $_ := set $grpcTLS "clientCAPath" "/etc/nantian-gw/grpc-tls/ca.crt" -}}
{{- end -}}
{{- $_ := set $grpcTLS "requireClientCert" .Values.controlplane.grpcTLS.requireClientCert -}}
{{- $_ := set $cfg "grpcTLS" $grpcTLS -}}
{{- end -}}
{{- toYaml $cfg }}
{{- end }}

{{/*
Dataplane config as YAML
*/}}
{{- define "nantian-gw.dataplane.configYaml" -}}
{{- $cfg := deepCopy .Values.dataplane.config -}}
{{- if .Values.dataplane.xdsTLS.enabled -}}
{{- $xds_tls := default (dict) $cfg.xds_tls -}}
{{- $_ := set $xds_tls "enabled" true -}}
{{- if not (get $xds_tls "ca_path") -}}
{{- $_ := set $xds_tls "ca_path" "/etc/nantian-gw/xds-tls/ca.crt" -}}
{{- end -}}
{{- if not (get $xds_tls "cert_path") -}}
{{- $_ := set $xds_tls "cert_path" "/etc/nantian-gw/xds-tls/tls.crt" -}}
{{- end -}}
{{- if not (get $xds_tls "key_path") -}}
{{- $_ := set $xds_tls "key_path" "/etc/nantian-gw/xds-tls/tls.key" -}}
{{- end -}}
{{- if and (not (get $xds_tls "domain_name")) .Values.dataplane.xdsTLS.domainName -}}
{{- $_ := set $xds_tls "domain_name" .Values.dataplane.xdsTLS.domainName -}}
{{- else if not (get $xds_tls "domain_name") -}}
{{- $_ := set $xds_tls "domain_name" (printf "%s-controlplane.%s.svc.cluster.local" (include "nantian-gw.name" .) (include "nantian-gw.namespace" .)) -}}
{{- end -}}
{{- $_ := set $cfg "xds_tls" $xds_tls -}}
{{- end -}}
{{- $admin_auth := default (dict) $cfg.admin_auth -}}
{{- if and (eq (include "nantian-gw.dataplaneAdminAuthUsesSecret" .) "true") (not (get $admin_auth "bearer_token_file")) -}}
{{- $_ := set $admin_auth "bearer_token_file" (include "nantian-gw.dataplaneAdminAuthFilePath" .) -}}
{{- $_ := set $cfg "admin_auth" $admin_auth -}}
{{- end -}}
{{- $sessionPersistence := default (dict) (get $cfg "session_persistence") -}}
{{- $sessionSecretKeyFile := trim (default "" (get $sessionPersistence "secret_key_file")) -}}
{{- $sessionInlineSecret := trim (default "" (get $sessionPersistence "shared_secret")) -}}
{{- if and (not $sessionSecretKeyFile) (not $sessionInlineSecret) -}}
{{- $_ := set $sessionPersistence "secret_key_file" (include "nantian-gw.dataplaneSessionPersistenceFilePath" .) -}}
{{- $_ := set $cfg "session_persistence" $sessionPersistence -}}
{{- end -}}
{{- if $cfg.control_plane_addr -}}
{{- $dpConfig := omit $cfg "control_plane_addr" -}}
control_plane_addr: {{ $cfg.control_plane_addr | quote }}
{{ toYaml $dpConfig }}
{{- else -}}
{{- $dpConfig := omit $cfg "control_plane_addr" -}}
control_plane_addr: "http://{{ include "nantian-gw.name" . }}-controlplane.{{ include "nantian-gw.namespace" . }}.svc.cluster.local:18080"
{{ toYaml $dpConfig }}
{{- end }}
{{- end }}

{{/*
Resolve the dashboard auth secret value.
1. Use user-provided authSecret if set
2. Reuse existing secret value (stable across upgrades)
3. Otherwise, generate a random value on first install
*/}}
{{- define "nantian-gw.dashboard-auth-secret" -}}
{{- if .Values.dashboard.authSecret }}
{{- .Values.dashboard.authSecret }}
{{- else }}
{{- $ns := include "nantian-gw.namespace" . }}
{{- $secret := lookup "v1" "Secret" $ns (printf "%s-dashboard-auth" (include "nantian-gw.name" .)) }}
{{- if $secret }}
{{- index $secret.data "auth-secret" | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Resolve the dataplane admin auth secret value.
1. Reuse the existing secret token when present
2. Otherwise, generate a random value on first install
*/}}
{{- define "nantian-gw.dataplane-admin-auth-token" -}}
{{- $ns := include "nantian-gw.namespace" . -}}
{{- $secretName := include "nantian-gw.dataplaneAdminAuthSecretName" . -}}
{{- $secretKey := .Values.dataplane.adminAuth.secretKey -}}
{{- $secret := lookup "v1" "Secret" $ns $secretName -}}
{{- if and $secret (index $secret.data $secretKey) -}}
{{- index $secret.data $secretKey | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end }}
