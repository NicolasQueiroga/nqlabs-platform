{{/*
Per-workload helpers for the multi-workload (`workloads:` map) mode.
Each helper receives a context dict: { "root": $, "name": <workload>, "wl": <spec> }.

A workload spec supports:
  kind: deployment|rollout         (default deployment)
  replicaCount: <int>              (default 1)
  image: {repository,tag,pullPolicy}   (defaults to top-level .Values.image)
  command: [], args: []
  container: { port: <int>, env: [] }
  podSecurityContext / securityContext: { enabled, ... }  (default top-level)
  probes: { readiness/liveness/startup: {enabled,path,port,timing} }
  resources: {}                    (default top-level .Values.resources)
  rollout: { strategy: { canary: {...} } }
  service: { enabled: true, port }  (port defaults to container.port)
  autoscaling / pdb / metrics: { enabled, ... }
  routes: { internal/public/preview }
*/}}

{{- define "nqlabs-service.wl.fullname" -}}
{{- printf "%s-%s" (include "nqlabs-service.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nqlabs-service.wl.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nqlabs-service.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
nqlabs.network/workload: {{ .name }}
{{- end -}}

{{- define "nqlabs-service.wl.labels" -}}
{{ include "nqlabs-service.labels" .root }}
nqlabs.network/workload: {{ .name }}
{{- end -}}

{{/* Container probes from a workload spec. */}}
{{- define "nqlabs-service.wl.probes" -}}
{{- $p := dig "probes" dict .wl -}}
{{- with $p }}
{{- if dig "readiness" "enabled" false . }}
readinessProbe:
  httpGet:
    path: {{ dig "readiness" "path" "/" . }}
    port: {{ dig "readiness" "port" "http" . }}
  {{- with dig "readiness" "timing" dict . }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- if dig "liveness" "enabled" false . }}
livenessProbe:
  httpGet:
    path: {{ dig "liveness" "path" "/" . }}
    port: {{ dig "liveness" "port" "http" . }}
  {{- with dig "liveness" "timing" dict . }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- if dig "startup" "enabled" false . }}
startupProbe:
  httpGet:
    path: {{ dig "startup" "path" "/" . }}
    port: {{ dig "startup" "port" "http" . }}
  {{- with dig "startup" "timing" dict . }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/* Deployment or Rollout for one workload. */}}
{{- define "nqlabs-service.wl.workload" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $wl := .wl -}}
{{- $isRollout := eq (dig "kind" "deployment" $wl) "rollout" -}}
{{- $image := dig "image" $root.Values.image $wl -}}
{{- $autoEnabled := dig "autoscaling" "enabled" false $wl -}}
{{- $psc := dig "podSecurityContext" $root.Values.podSecurityContext $wl -}}
{{- $sc := dig "securityContext" $root.Values.securityContext $wl -}}
{{- $port := dig "container" "port" 0 $wl -}}
apiVersion: {{ $isRollout | ternary "argoproj.io/v1alpha1" "apps/v1" }}
kind: {{ $isRollout | ternary "Rollout" "Deployment" }}
metadata:
  name: {{ include "nqlabs-service.wl.fullname" . }}
  labels:
    {{- include "nqlabs-service.wl.labels" . | nindent 4 }}
spec:
  {{- if not $autoEnabled }}
  replicas: {{ dig "replicaCount" 1 $wl }}
  {{- end }}
  {{- if $isRollout }}
  strategy:
    canary:
      {{- toYaml (dig "rollout" "strategy" "canary" (dict "maxSurge" "25%" "maxUnavailable" 0) $wl) | nindent 6 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "nqlabs-service.wl.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "nqlabs-service.wl.labels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "nqlabs-service.serviceAccountName" $root }}
      {{- with $root.Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $psc.enabled }}
      securityContext:
        {{- omit $psc "enabled" | toYaml | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ $name }}
          image: "{{ $image.repository }}:{{ $image.tag }}"
          imagePullPolicy: {{ dig "pullPolicy" "IfNotPresent" $image }}
          {{- with dig "command" list $wl }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with dig "args" list $wl }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if $port }}
          ports:
            - name: http
              containerPort: {{ $port }}
              protocol: TCP
          {{- end }}
          {{- with dig "container" "env" list $wl }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- $df := include "nqlabs-service.depsEnvFrom" $root }}
          {{- if $df }}
          {{- $df | nindent 10 }}
          {{- end }}
          {{- if $sc.enabled }}
          securityContext:
            {{- omit $sc "enabled" | toYaml | nindent 12 }}
          {{- end }}
          {{- $probes := include "nqlabs-service.wl.probes" . }}
          {{- if $probes }}
          {{- $probes | nindent 10 }}
          {{- end }}
          resources:
            {{- toYaml (dig "resources" $root.Values.resources $wl) | nindent 12 }}
{{- end -}}

{{/* Service for one workload (only when it exposes a port). */}}
{{- define "nqlabs-service.wl.service" -}}
{{- $wl := .wl -}}
{{- $port := dig "container" "port" 0 $wl -}}
{{- $svcPort := dig "service" "port" $port $wl -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "nqlabs-service.wl.fullname" . }}
  labels:
    {{- include "nqlabs-service.wl.labels" . | nindent 4 }}
spec:
  type: {{ dig "service" "type" "ClusterIP" $wl }}
  ports:
    - name: http
      port: {{ $svcPort }}
      targetPort: http
      protocol: TCP
  selector:
    {{- include "nqlabs-service.wl.selectorLabels" . | nindent 4 }}
{{- end -}}

{{/* HPA for one workload. */}}
{{- define "nqlabs-service.wl.hpa" -}}
{{- $wl := .wl -}}
{{- $a := .wl.autoscaling -}}
{{- $isRollout := eq (dig "kind" "deployment" $wl) "rollout" -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "nqlabs-service.wl.fullname" . }}
  labels:
    {{- include "nqlabs-service.wl.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: {{ $isRollout | ternary "argoproj.io/v1alpha1" "apps/v1" }}
    kind: {{ $isRollout | ternary "Rollout" "Deployment" }}
    name: {{ include "nqlabs-service.wl.fullname" . }}
  minReplicas: {{ dig "minReplicas" 1 $a }}
  maxReplicas: {{ dig "maxReplicas" 3 $a }}
  metrics:
    {{- if dig "targetCPUUtilizationPercentage" 0 $a }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $a.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if dig "targetMemoryUtilizationPercentage" 0 $a }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ $a.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end -}}

{{/* PDB for one workload. */}}
{{- define "nqlabs-service.wl.pdb" -}}
{{- $p := .wl.pdb -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "nqlabs-service.wl.fullname" . }}
  labels:
    {{- include "nqlabs-service.wl.labels" . | nindent 4 }}
spec:
  {{- if dig "minAvailable" 0 $p }}
  minAvailable: {{ $p.minAvailable }}
  {{- else if dig "maxUnavailable" 0 $p }}
  maxUnavailable: {{ $p.maxUnavailable }}
  {{- else }}
  minAvailable: 1
  {{- end }}
  selector:
    matchLabels:
      {{- include "nqlabs-service.wl.selectorLabels" . | nindent 6 }}
{{- end -}}

{{/* ServiceMonitor for one workload. */}}
{{- define "nqlabs-service.wl.servicemonitor" -}}
{{- $m := .wl.metrics -}}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "nqlabs-service.wl.fullname" . }}
  labels:
    {{- include "nqlabs-service.wl.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "nqlabs-service.wl.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: {{ dig "port" "http" $m }}
      path: {{ dig "path" "/metrics" $m }}
      interval: {{ dig "interval" "30s" $m }}
{{- end -}}

{{/* Internal/public/preview HTTPRoutes for one workload. */}}
{{- define "nqlabs-service.wl.routes" -}}
{{- $ctx := . -}}
{{- $wl := .wl -}}
{{- $svcPort := dig "service" "port" (dig "container" "port" 80 $wl) $wl -}}
{{- range $class := (list "internal" "public" "preview") }}
{{- $r := dig $class dict $wl.routes }}
{{- if and $r (dig "enabled" false $r) }}
{{- if not (dig "host" "" $r) }}{{- fail (printf "workload route %s.host required when enabled" $class) }}{{- end }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "nqlabs-service.wl.fullname" $ctx }}-{{ $class }}
  labels:
    {{- include "nqlabs-service.wl.labels" $ctx | nindent 4 }}
    nqlabs.network/route-class: {{ $class }}
  annotations:
    external-dns.alpha.kubernetes.io/hostname: {{ $r.host | quote }}
spec:
  parentRefs:
    - name: {{ dig "gateway" "name" "platform-gateway" $r }}
      namespace: {{ dig "gateway" "namespace" "platform" $r }}
      sectionName: {{ dig "gateway" "sectionName" "https" $r }}
  hostnames:
    - {{ $r.host | quote }}
  rules:
    - matches:
        {{- range (dig "paths" (list (dict "type" "PathPrefix" "value" "/")) $r) }}
        - path:
            type: {{ .type }}
            value: {{ .value | quote }}
        {{- end }}
      backendRefs:
        - name: {{ include "nqlabs-service.wl.fullname" $ctx }}
          port: {{ $svcPort }}
      {{- with (dig "timeouts" (dig "route" "timeouts" dict $ctx.root.Values) $r) }}
      timeouts:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}
{{- end -}}
