#!/usr/bin/env bash
# Regenerate the reference raw-Kubernetes manifests from the Helm chart.
#
# These are published so operators can review exactly what the chart produces
# and deploy without Helm (`kubectl apply -f socket-firewall.yaml`). Re-run this
# after changing chart templates, values, or the pinned appVersion.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHART="$(cd "$HERE/.." && pwd)"

helm template socket-firewall "$CHART" \
  --namespace socket-firewall \
  -f "$HERE/example-values.yaml" \
  > "$HERE/socket-firewall.yaml"

echo "Wrote $HERE/socket-firewall.yaml"
