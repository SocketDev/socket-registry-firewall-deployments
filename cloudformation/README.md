# CloudFormation — Socket Registry Firewall on AWS (EKS)

> **Status: DRAFT, untested.** These templates are a work in progress and have not been deployed yet. Validate in a non-production account before relying on them.

## Background

Reference CloudFormation for deploying the Socket Registry Firewall on **AWS EKS** (firewall + Redis, DNS-override routing, self-signed certs, fail-open). This is the EKS companion to the existing per-platform deployment templates (ECS Fargate, GCP Cloud Run, Azure Container Apps).

On EKS the firewall is the **Helm chart** (`../helm`), which already supports DNS-override, self-signed CA generation, and Redis/TLS — so most of the work is standing up the AWS infrastructure and installing the chart, not re-implementing the workload.

## Layout

| File | Purpose |
|------|---------|
| `eks-cluster.yaml` | **Greenfield wrapper** — VPC + EKS cluster + node group + OIDC provider. Skip if you already run a cluster. |
| `firewall-eks.yaml` | **Shared base** — ElastiCache Redis + Socket token (Secrets Manager) + IRSA role; emits the `helm upgrade --install` command. |
| `values/dns-override.values.yaml` | Example Helm values (DNS-override + Redis + self-signed certs). Behavioral defaults stay synced with `helm/values.yaml`; image pinned to `2.0.13`. |

## Cases

- **Greenfield (no cluster):** deploy `eks-cluster.yaml`, then `firewall-eks.yaml` (wire its outputs in), then run the emitted Helm command.
- **Existing cluster:** deploy `firewall-eks.yaml` only (pass your existing `ClusterName` / `VpcId` / subnets / cluster security group / OIDC), then Helm.

The base is identical in both cases — the wrapper only adds the cluster/VPC layer.

## Helm install: handoff vs one-shot

The base template currently takes the **handoff** approach: CloudFormation provisions the infrastructure and outputs the exact `helm upgrade --install` command to run. The alternative is **one-shot**, where the stack runs Helm itself via a CodeBuild-backed custom resource (CodeBuild installs helm/kubectl, runs `aws eks update-kubeconfig`, then `helm upgrade --install`; a small Lambda signals CloudFormation). One-shot is a single-deploy experience but adds a moving part and requires the CodeBuild role be added to the cluster's EKS access entries.

## Config model

On EKS the Helm chart renders the firewall config into a **ConfigMap**. The stack injects install-time values for the ElastiCache endpoint (`redis.host`), the Socket token (`socket.apiToken`, read from Secrets Manager), and the firewall image tag (`image.tag`, default `2.0.13`). Chart version defaults to `0.11.1`.

## Known DRAFT caveats

- **Untested** — no template here has been deployed yet.
- `eks-cluster.yaml`'s OIDC `ThumbprintList` is a placeholder — confirm it for your issuer, or associate the provider with `eksctl utils associate-iam-oidc-provider`.
- ElastiCache transit encryption assumes the firewall image trusts Amazon's CA for `redis.ssl`; if not, mount the CA or set `redis.sslVerify: false`.
- The example values file enables npm + pypi only — adjust to your ecosystems.
