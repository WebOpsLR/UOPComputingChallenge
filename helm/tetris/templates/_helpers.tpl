{{/*
Expand the name of the chart.
*/}}
{{- define "tetris.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tetris.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "tetris.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to all resources.
*/}}
{{- define "tetris.labels" -}}
app.kubernetes.io/name: {{ include "tetris.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Selector labels used to match pods to the Deployment/Service.
*/}}
{{- define "tetris.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tetris.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
