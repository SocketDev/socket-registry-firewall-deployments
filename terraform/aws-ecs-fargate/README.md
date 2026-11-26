# Socket Firewall - AWS ECS Fargate (Terraform)

Terraform template for deploying the [Socket Registry Firewall](https://docs.socket.dev/docs/socket-firewall-enterprise-registry-mode) on AWS ECS Fargate.

## What it provisions

- ECS Cluster with Fargate launch type
- Internal Application Load Balancer (HTTPS)
- Secrets Manager for the Socket API token
- CloudWatch log group
- Security groups (ALB + ECS tasks)
- Auto-scaling (CPU-based, target tracking)
- IAM roles (task execution + task)
- Deployment circuit breaker with automatic rollback

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate permissions
- An existing VPC with public and private subnets
- An ACM certificate for the ALB HTTPS listener
- A Socket.dev API token ([create one here](https://socket.dev/dashboard/org/settings/api-tokens)) with `packages` and `entitlements:list` scopes

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

## Inputs

See `variables.tf` for all configurable inputs with descriptions and defaults.

Key variables:
- `socket_api_token` - Socket.dev API token (required)
- `vpc_id` - VPC to deploy into (required)
- `private_subnet_ids` - Subnets for ECS tasks (required)
- `public_subnet_ids` - Subnets for the ALB (required)
- `acm_certificate_arn` - ACM cert for HTTPS (required)
- `registries` - Map of registries to proxy (default: `{npm = "https://registry.npmjs.org"}`)
- `desired_count` - Number of tasks and the autoscaling minimum (default: 3)
- `cpu` / `memory` - Task size (default: 4 vCPU / 8 GB). The nginx worker count follows `cpu`.

## Sizing

The defaults (3 tasks of 4 vCPU and 8 GB each) are the starting point from the [sizing guide](https://docs.socket.dev/docs/socket-firewall-enterprise-registry-mode-sizing). Raise `desired_count` for larger developer counts; autoscaling allows up to 4 times that. The template sets the nginx worker count from `cpu`.

## Registries

The `registries` variable controls which package registries the firewall proxies. Each entry creates a path-based route on the ALB (e.g., `/npm`, `/pypi`).

```hcl
registries = {
  npm   = "https://registry.npmjs.org"
  pypi  = "https://pypi.org"
  maven = "https://repo1.maven.org/maven2"
}
```

Configure your package manager to use the firewall as its registry:

```bash
# npm
npm config set registry https://<alb-dns-name>/npm

# pip
pip install --index-url https://<alb-dns-name>/pypi/simple <package>
```

## Outputs

- `alb_dns_name` - DNS name of the ALB (point your registry DNS records here)
- `alb_zone_id` - Route 53 zone ID (for alias records)
- `ecs_cluster_name` / `ecs_service_name` - For monitoring and debugging
- `log_group_name` - CloudWatch log group

## Verify the deployment

After `terraform apply`, verify the firewall is running from inside the VPC (the ALB is internal):

```bash
# Health check — should include "path-routing" in the response
curl -sk https://<alb-dns-name>/health
# Expected: SocketFirewall/x.x.x - Health OK - path-routing (...)

# Test a safe package (--strict-ssl=false only needed with self-signed certs)
npm install lodash --registry https://<alb-dns-name>/npm --strict-ssl=false

# Test a blocked package
# IMPORTANT: clear npm cache first, or cached tarballs bypass the firewall
npm cache clean --force
npm install peacenotwar@9.1.3 --registry https://<alb-dns-name>/npm --strict-ssl=false --prefer-online
# Expected: E403 "Blocked by Security Policy"
```

> **Note:** `--strict-ssl=false` is only needed when using a self-signed ACM certificate. With a valid ACM cert and a DNS alias (e.g., `registry.internal.company.com`), you can omit it.

## Troubleshooting

**Tasks keep restarting / circuit breaker rolls back**
- Check CloudWatch logs: `aws logs tail /ecs/<name-prefix> --follow`
- Common causes: invalid API token, container can't reach the internet (check NAT gateway / public IP settings)

**npm returns 404 for all packages**
- Verify the health endpoint returns `path-routing (...)` in the response. If it just says `Health OK` without `path-routing`, the socket.yml config is not loading.
- Confirm you're using the `/npm` path prefix: `https://<alb-dns-name>/npm/<package>`

**Packages install but aren't being scanned**
- Verify your API token has the `packages` and `entitlements:list` scopes
- Check CloudWatch logs for `Firewall access validation failed` or `401` errors
- With `socket_fail_open = true` (the default), invalid tokens silently pass all packages through

**Secrets Manager conflict on re-deploy**
- If `terraform destroy` followed by `terraform apply` fails with "secret already scheduled for deletion," force-delete the old secret:
  ```bash
  aws secretsmanager delete-secret --secret-id <secret-name> --force-delete-without-recovery
  ```

## Other deployment options

- **Already on Kubernetes?** Use the [Helm chart](../../helm), or the [EKS CloudFormation templates](../../cloudformation)
- **On GCP?** See the [Cloud Run template](../gcp-cloud-run)
- **On Azure?** See the [Container Apps template](../azure-container-apps)
