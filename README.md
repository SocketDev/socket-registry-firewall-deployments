# socket-registry-firewall-deployments

Deployment templates for the Socket Registry Firewall.

## Layout

- `helm/` — Kubernetes Helm chart (migrated from `socketdev-demo/socket-firewall-helm` with full commit history).
- `cloudformation/` — AWS CloudFormation templates (in progress).
- `terraform/` — Terraform templates.
  - `terraform/azure-container-apps/` — Azure Container Apps (migrated from
    `socketdev-demo/socket-firewall-azure-container-apps` with full commit history).

## Helm chart publishing

The chart is **still published from `socketdev-demo/socket-firewall-helm`** via GitHub Pages at
`https://socketdev-demo.github.io/socket-firewall-helm/`. That endpoint is unchanged, so existing
`helm repo add` users are unaffected.

This repository is the source of truth for the chart. Release CI here is intended to publish chart
packages to the old repo's `gh-pages` branch so the download URL stays stable (setup pending). The
longer-term plan to decouple the download URL from that repo is tracked in CE-238.
