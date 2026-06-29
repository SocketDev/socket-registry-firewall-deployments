{{/*
Expand the name of the chart.
*/}}
{{- define "socket-firewall.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "socket-firewall.fullname" -}}
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
Fully-qualified firewall image reference.
The tag defaults to the chart's appVersion so the firewall version is defined in
exactly one place (Chart.yaml appVersion). Override via image.tag in values.yaml.
*/}}
{{- define "socket-firewall.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "socket-firewall.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "socket-firewall.labels" -}}
helm.sh/chart: {{ include "socket-firewall.chart" . }}
{{ include "socket-firewall.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "socket-firewall.selectorLabels" -}}
app.kubernetes.io/name: {{ include "socket-firewall.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "socket-firewall.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "socket-firewall.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for Socket API token
*/}}
{{- define "socket-firewall.secretName" -}}
{{- if .Values.socket.existingSecret }}
{{- .Values.socket.existingSecret }}
{{- else }}
{{- include "socket-firewall.fullname" . }}-api-token
{{- end }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "socket-firewall.redisSecretName" -}}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- include "socket-firewall.fullname" . }}-redis
{{- end }}
{{- end }}

{{/*
Splunk secret name
*/}}
{{- define "socket-firewall.splunkSecretName" -}}
{{- if .Values.splunk.existingSecret }}
{{- .Values.splunk.existingSecret }}
{{- else }}
{{- include "socket-firewall.fullname" . }}-splunk
{{- end }}
{{- end }}

{{/*
TLS secret name
*/}}
{{- define "socket-firewall.tlsSecretName" -}}
{{- if .Values.tls.existingSecret }}
{{- .Values.tls.existingSecret }}
{{- else }}
{{- include "socket-firewall.fullname" . }}-tls
{{- end }}
{{- end }}

{{/*
Chart-managed upstream-tokens Secret name
*/}}
{{- define "socket-firewall.upstreamTokensSecretName" -}}
{{- include "socket-firewall.fullname" . }}-upstream-tokens
{{- end }}
