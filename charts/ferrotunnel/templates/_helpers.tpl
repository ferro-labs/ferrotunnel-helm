{{/* Expand the name of the chart. */}}
{{- define "ferrotunnel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Create a default fully qualified app name. */}}
{{- define "ferrotunnel.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Create chart name and version as used by the chart label. */}}
{{- define "ferrotunnel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "ferrotunnel.labels" -}}
helm.sh/chart: {{ include "ferrotunnel.chart" . }}
{{ include "ferrotunnel.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with omit .Values.commonLabels "helm.sh/chart" "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/version" "app.kubernetes.io/managed-by" "app.kubernetes.io/component" }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Selector labels. */}}
{{- define "ferrotunnel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ferrotunnel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Service account name. */}}
{{- define "ferrotunnel.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "ferrotunnel.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Token secret name. */}}
{{- define "ferrotunnel.tokenSecretName" -}}
{{- default (printf "%s-auth" (include "ferrotunnel.fullname" .)) .Values.auth.existingSecret -}}
{{- end -}}

{{/* TLS secret name. */}}
{{- define "ferrotunnel.tlsSecretName" -}}
{{- required "tls.existingSecret is required when tls.enabled=true" .Values.tls.existingSecret -}}
{{- end -}}

{{/* Common annotations. */}}
{{- define "ferrotunnel.commonAnnotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end -}}
{{- end -}}

{{/* Optional Service spec fields shared by all FerroTunnel Services. */}}
{{- define "ferrotunnel.serviceSpecFields" -}}
{{- if and (eq .type "LoadBalancer") .loadBalancerIP }}
loadBalancerIP: {{ .loadBalancerIP | quote }}
{{- end }}
{{- if and (eq .type "LoadBalancer") .loadBalancerClass }}
loadBalancerClass: {{ .loadBalancerClass | quote }}
{{- end }}
{{- if and (or (eq .type "NodePort") (eq .type "LoadBalancer")) .externalTrafficPolicy }}
externalTrafficPolicy: {{ .externalTrafficPolicy }}
{{- end }}
{{- if and (ne .type "ExternalName") .internalTrafficPolicy }}
internalTrafficPolicy: {{ .internalTrafficPolicy }}
{{- end }}
{{- if and (ne .type "ExternalName") .ipFamilyPolicy }}
ipFamilyPolicy: {{ .ipFamilyPolicy }}
{{- end }}
{{- if and (ne .type "ExternalName") .ipFamilies }}
ipFamilies:
{{- toYaml .ipFamilies | nindent 2 }}
{{- end }}
{{- if and (ne .type "ExternalName") .sessionAffinity }}
sessionAffinity: {{ .sessionAffinity }}
{{- end }}
{{- end -}}

{{/* Optional Service port fields shared by all FerroTunnel Services. */}}
{{- define "ferrotunnel.servicePortFields" -}}
{{- if and (or (eq .type "NodePort") (eq .type "LoadBalancer")) (ne .nodePort nil) }}
nodePort: {{ .nodePort }}
{{- end }}
{{- end -}}
