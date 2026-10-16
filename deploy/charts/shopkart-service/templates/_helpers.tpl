{{- define "shopkart-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shopkart-service.fullname" -}}
{{- .Values.nameOverride | default .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shopkart-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shopkart-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "shopkart-service.labels" -}}
{{ include "shopkart-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: shopkart
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "shopkart-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ include "shopkart-service.fullname" . }}
{{- else -}}
default
{{- end -}}
{{- end -}}
