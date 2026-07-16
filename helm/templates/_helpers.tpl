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
Whether the Prometheus metrics port/annotations/ServiceMonitor should be exposed.
Returns the string "true" when metrics should be exposed, otherwise empty.

The /metrics endpoint only exists in firewall image >= metrics.minImageVersion
(default 1.1.343). Older semver tags are gated out. Non-semver tags (e.g.
"latest" or a digest) can't be compared, so they are assumed new enough and are
NOT gated out (fail-open) — this avoids aborting templating, since semverCompare
errors on an unparseable string. The strict, anchored regex guarantees we never
hand semverCompare a tag it would reject (that includes 4-component tags).
*/}}
{{- define "socket-firewall.metricsExposed" -}}
{{- if .Values.metrics.enabled -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $floor := .Values.metrics.minImageVersion | default "1.1.343" -}}
{{- if regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z-.]+)?(\\+[0-9A-Za-z-.]+)?$" $tag -}}
{{- if semverCompare (printf ">=%s" $floor) $tag -}}true{{- end -}}
{{- else -}}true{{- end -}}
{{- end -}}
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
Bearer token secret name (client auth gate)
*/}}
{{- define "socket-firewall.bearerTokenSecretName" -}}
{{- if .Values.socket.bearerTokenExistingSecret }}
{{- .Values.socket.bearerTokenExistingSecret }}
{{- else }}
{{- include "socket-firewall.fullname" . }}-bearer-token
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
