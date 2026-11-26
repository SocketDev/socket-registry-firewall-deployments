# socket-registry-firewall-deployments

Deployment templates for the Socket Registry Firewall.

## Templates

| Platform | Template | Notes |
| -------- | -------- | ----- |
| Kubernetes (any) | [`helm/`](helm) | Published at `https://socketdev-demo.github.io/socket-firewall-helm/` |
| AWS EKS | [`cloudformation/`](cloudformation) | VPC, EKS, and ElastiCache, then the Helm chart. Draft, untested |
| AWS ECS Fargate | [`terraform/aws-ecs-fargate/`](terraform/aws-ecs-fargate) | Fargate service behind an internal ALB |
| Azure Container Apps | [`terraform/azure-container-apps/`](terraform/azure-container-apps) | Container App with Key Vault and VNet integration |
| GCP Cloud Run | [`terraform/gcp-cloud-run/`](terraform/gcp-cloud-run) | Cloud Run v2 service with Secret Manager |

The Terraform templates default to the sizing guide's baseline of 3 replicas with 4 vCPU and 8 GiB each. The Helm chart defaults to 1 replica, so set `replicaCount` for production. To size for your developer count, Redis, and high availability, see [Sizing and High Availability](https://docs.socket.dev/docs/socket-firewall-enterprise-registry-mode-sizing).

## Layout

- `helm/` — Kubernetes Helm chart (migrated from `socketdev-demo/socket-firewall-helm` with full commit history).
- `cloudformation/` — AWS CloudFormation templates for EKS (in progress).
- `terraform/` — Terraform templates for ECS Fargate, Azure Container Apps, and GCP Cloud Run (moved from the matching `socketdev-demo/socket-firewall-*` repositories).

## Helm chart publishing

The chart is **still published from `socketdev-demo/socket-firewall-helm`** via GitHub Pages at
`https://socketdev-demo.github.io/socket-firewall-helm/`. That endpoint is unchanged, so existing
`helm repo add` users are unaffected.

This repository is the source of truth for the chart. Release CI here is intended to publish chart
packages to the old repo's `gh-pages` branch so the download URL stays stable (setup pending). The
longer-term plan to decouple the download URL from that repo is tracked in CE-238.
