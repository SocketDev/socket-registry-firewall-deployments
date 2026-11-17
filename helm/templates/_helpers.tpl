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
Read one socket.clientMtls on/off value. Prints "true" or "false".
Call: include "socket-firewall.clientMtlsBool" (dict "root" . "key" "require" "default" "true")

Accepts a boolean or the strings "true"/"false" (what --set-string and a quoted
value produce). Only an unset or null value takes the given default. Anything
else fails the render, the empty string included: these values switch an auth
gate, so a typo, or a variable that expands to nothing in --set or inside quotes,
must not turn it on or off silently. Plain template truthiness reads the string
"false" as true.

A blank value in a values file (`enabled:`) cannot be caught here: it is YAML
null, and Helm drops a null key before templates run, so it looks the same as
the missing key below and takes the default.

socket.clientMtls itself may be missing: `helm upgrade --reuse-values` keeps the
values of the installed release, which predate this block. Only a missing or
null block counts as empty. `default dict` is not used for that: it would also
swallow false, 0, "" and [], which must fail the map check.
*/}}
{{- define "socket-firewall.clientMtlsBool" -}}
{{- $mtls := .root.Values.socket.clientMtls -}}
{{- if kindIs "invalid" $mtls -}}
{{- $mtls = dict -}}
{{- end -}}
{{- if not (kindIs "map" $mtls) -}}
{{- fail (printf "socket.clientMtls must be a map of settings (enabled, require, ...), got %s" (toJson $mtls | trunc 40)) -}}
{{- end -}}
{{- $raw := index $mtls .key -}}
{{- $text := toString $raw -}}
{{- if kindIs "invalid" $raw -}}
{{- .default -}}
{{- else if has $text (list "true" "false") -}}
{{- $text -}}
{{- else -}}
{{- fail (printf "socket.clientMtls.%s must be true or false, got %q" .key $text) -}}
{{- end -}}
{{- end }}

{{/*
Whether client certificate (mTLS) auth is on. Prints "true" or "false".
*/}}
{{- define "socket-firewall.clientMtlsEnabled" -}}
{{- include "socket-firewall.clientMtlsBool" (dict "root" . "key" "enabled" "default" "false") -}}
{{- end }}

{{/*
Client certificate (mTLS) auth: render-time checks. Renders nothing when the
configuration is valid.

The three on/off values are checked whether or not mTLS is enabled, so a typo
fails when it is written, not on the later upgrade that turns mTLS on.

An image older than 2.15.0 ignores socket.client_mtls and checks no certificate,
so the release would look protected while admitting everyone. The check reads
the major.minor the tag starts with (2.14.2, v2.14.2, 2.14, 2.14.2-internal,
2.14.2@sha256:...) and compares the two as numbers. semverCompare is not used:
it errors on a digest suffix and on a four-part tag, and it reads a suffixed
tag as a pre-release, so 2.15.0-rc1 and 2.20.1-internal would count as older
than 2.15.0. A tag that does not start with major.minor
("latest", a bare digest, a custom name) cannot be compared and is assumed new
enough. A bare major is not read: a short commit hash can start with digits.
*/}}
{{- define "socket-firewall.validateClientMtls" -}}
{{- $enabled := eq (include "socket-firewall.clientMtlsEnabled" .) "true" -}}
{{- /* Evaluated for its own check only: a bad value fails here, with its own message. */ -}}
{{- $_ := include "socket-firewall.clientMtlsBool" (dict "root" . "key" "require" "default" "true") -}}
{{- $skipVersion := eq (include "socket-firewall.clientMtlsBool" (dict "root" . "key" "skipImageVersionCheck" "default" "false")) "true" -}}
{{- $tag := toString (.Values.image.tag | default .Chart.AppVersion) -}}
{{- $version := regexFind "^[vV]?[0-9]+\\.[0-9]+" $tag | trimPrefix "v" | trimPrefix "V" -}}
{{- if and $enabled (not $skipVersion) $version -}}
{{- $parts := splitList "." $version -}}
{{- $major := atoi (index $parts 0) -}}
{{- $minor := atoi (index $parts 1) -}}
{{- if or (lt $major 2) (and (eq $major 2) (lt $minor 15)) -}}
{{- fail (printf "socket.clientMtls.enabled is true but image tag %s is older than 2.15.0: that image ignores socket.clientMtls, so no client certificate would be checked. If the tag is your own name for an image you have confirmed is 2.15.0 or newer, set socket.clientMtls.skipImageVersionCheck=true" $tag) -}}
{{- end -}}
{{- end -}}
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
