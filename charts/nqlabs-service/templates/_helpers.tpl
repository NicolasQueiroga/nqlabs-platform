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
