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
Dataplane pod security context with low-port binding sysctl.
*/}}
{{- define "nantian-gw.dataplanePodSecurityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
  sysctls:
    - name: net.ipv4.ip_unprivileged_port_start
      value: "0"
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
Controlplane config as YAML
*/}}
{{- define "nantian-gw.controlplane.configYaml" -}}
{{- $cfg := deepCopy .Values.controlplane.config -}}
{{- $dashboardApi := default (dict) $cfg.dashboardApi -}}
{{- if not (get $dashboardApi "dataplaneAdminUrl") -}}
{{- $_ := set $dashboardApi "dataplaneAdminUrl" (printf "http://%s-dataplane-admin.%s.svc.cluster.local:19080" (include "nantian-gw.name" .) (include "nantian-gw.namespace" .)) -}}
{{- $_ := set $cfg "dashboardApi" $dashboardApi -}}
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
{{- $xdsTLS := default (dict) $cfg.xdsTls -}}
{{- $_ := set $xdsTLS "enabled" true -}}
{{- if not (get $xdsTLS "caPath") -}}
{{- $_ := set $xdsTLS "caPath" "/etc/nantian-gw/xds-tls/ca.crt" -}}
{{- end -}}
{{- if not (get $xdsTLS "certPath") -}}
{{- $_ := set $xdsTLS "certPath" "/etc/nantian-gw/xds-tls/tls.crt" -}}
{{- end -}}
{{- if not (get $xdsTLS "keyPath") -}}
{{- $_ := set $xdsTLS "keyPath" "/etc/nantian-gw/xds-tls/tls.key" -}}
{{- end -}}
{{- if and (not (get $xdsTLS "domainName")) .Values.dataplane.xdsTLS.domainName -}}
{{- $_ := set $xdsTLS "domainName" .Values.dataplane.xdsTLS.domainName -}}
{{- end -}}
{{- $_ := set $cfg "xdsTls" $xdsTLS -}}
{{- end -}}
{{- if $cfg.controlPlaneAddr -}}
{{- $dpConfig := omit $cfg "controlPlaneAddr" -}}
controlPlaneAddr: {{ $cfg.controlPlaneAddr | quote }}
{{ toYaml $dpConfig }}
{{- else -}}
{{- $dpConfig := omit $cfg "controlPlaneAddr" -}}
controlPlaneAddr: "http://{{ include "nantian-gw.name" . }}-controlplane-grpc.{{ include "nantian-gw.namespace" . }}.svc.cluster.local:18080"
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
