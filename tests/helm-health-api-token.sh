#!/bin/sh
# Renders the chart and checks how the operator (health API) token is wired.
set -eu
cd "$(dirname "$0")/.."
r() { helm template t helm --set socket.apiToken=x "$@"; }
fail() { echo "FAIL: $1"; exit 1; }

out=$(r --set socket.healthApiTokenExistingSecret=op-tok)
echo "$out" | grep -A4 'name: SOCKET_HEALTH_API_TOKEN' | grep -q 'name: op-tok' || fail "env not from secret"
echo "$out" | grep -A4 'name: SOCKET_HEALTH_API_TOKEN' | grep -q 'key: SOCKET_HEALTH_API_TOKEN' || fail "default key"
echo "$out" | grep -q 'health_api_token' && fail "token rendered into ConfigMap"
a1=$(echo "$out" | grep 'checksum/health-api-token-ref')
[ -n "$a1" ] || fail "no rollout annotation"
a2=$(r --set socket.healthApiTokenExistingSecret=op-tok --set socket.healthApiTokenExistingSecretKey=k | grep 'checksum/health-api-token-ref')
[ "$a1" != "$a2" ] || fail "annotation ignores key change"

out=$(r)
echo "$out" | grep -q 'SOCKET_HEALTH_API_TOKEN\|health-api-token-ref' && fail "rendered without the secret set"

r --set socket.healthApiToken=plain | grep -q 'health_api_token: "plain"' || fail "string value broken"
echo "ok"
