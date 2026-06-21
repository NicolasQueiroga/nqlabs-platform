{{- define "nqlabs-service.name" -}}
{{- default .Chart.Name .Values.app.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nqlabs-service.fullname" -}}
{{- $name := include "nqlabs-service.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "nqlabs-service.labels" -}}
app.kubernetes.io/name: {{ include "nqlabs-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nqlabs-platform
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- if .Values.environment.name }}
nqlabs.network/environment: {{ .Values.environment.name | quote }}
{{- end }}
{{- end -}}

{{- define "nqlabs-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nqlabs-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "nqlabs-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- include "nqlabs-service.fullname" . -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Container HTTP probes. Renders readiness/liveness/startup probes for each entry
whose `enabled` is true. Default values disable all probes so existing simple
services (no health endpoint) are unaffected. `timing` is an optional free-form
map (initialDelaySeconds, periodSeconds, timeoutSeconds, failureThreshold, ...).
*/}}
{{- define "nqlabs-service.probes" -}}
{{- with .Values.probes }}
{{- if .readiness.enabled }}
readinessProbe:
  httpGet:
    path: {{ .readiness.path | default "/" }}
    port: {{ .readiness.port | default "http" }}
  {{- with .readiness.timing }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- if .liveness.enabled }}
livenessProbe:
  httpGet:
    path: {{ .liveness.path | default "/" }}
    port: {{ .liveness.port | default "http" }}
  {{- with .liveness.timing }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- if .startup.enabled }}
startupProbe:
  httpGet:
    path: {{ .startup.path | default "/" }}
    port: {{ .startup.port | default "http" }}
  {{- with .startup.timing }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/* envFrom the dependency Secret, when dependencies.secrets is declared. */}}
{{- define "nqlabs-service.depsEnvFrom" -}}
{{- if .Values.dependencies.secrets }}
envFrom:
  - secretRef:
      name: {{ include "nqlabs-service.fullname" . }}-deps
{{- end }}
{{- end -}}
