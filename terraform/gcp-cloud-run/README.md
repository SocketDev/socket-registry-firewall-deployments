# Socket Firewall - GCP Cloud Run (Terraform)

Terraform template for deploying the [Socket Registry Firewall](https://docs.socket.dev/docs/socket-firewall-enterprise-registry-mode) on GCP Cloud Run.

## What it provisions

- Cloud Run v2 service (internal-only ingress by default, configurable)
- Secret Manager secrets for the API token, generated socket.yml, and optional SSL certificates
- IAM bindings so both the Cloud Run service agent and the revision's runtime service account can read the secrets
- VPC networking (connector or Direct VPC egress)
- Instance auto-scaling

## Prerequisites

- Terraform >= 1.5
- `gcloud` CLI configured with appropriate permissions
- A GCP project with Cloud Run and Secret Manager APIs enabled
- A VPC network (for internal-only access)
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
- `project_id` - GCP project ID (required)
- `socket_api_token` - Socket.dev API token (required, pass via `TF_VAR_socket_api_token`)
- `domain` - Hostname for path-based routing (required, single hostname)
- `registries` - Map of registry name to upstream URL (default: npm only)
- `ingress` - Cloud Run ingress (default: internal only; set `INGRESS_TRAFFIC_ALL` for an off-VPC pilot)
- `invoker_members` - IAM members allowed to invoke the service (package clients need `allUsers`)
- `webhook_url` - Optional endpoint that receives a JSON event per blocked package
- `socket_fail_open` - Allow requests when Socket API is unreachable (default: true)
- `ssl_cert` / `ssl_key` - Optional; Cloud Run terminates TLS, so the container's HTTPS listener normally uses the image's bundled cert
- `min_instances` / `max_instances` - Scaling bounds (default: 3 / 10)
- `cpu` / `memory` - Container resources (default: 4 / 8Gi). The nginx worker count follows `cpu`.

## Sizing

The defaults (3 instances of 4 CPU and 8Gi each) are the starting point from the [sizing guide](https://docs.socket.dev/docs/socket-firewall-enterprise-registry-mode-sizing). Raise `min_instances` for larger developer counts, and keep about 2Gi of memory per CPU. The template sets the nginx worker count from `cpu`.

## Registries

The `registries` variable controls path-based routing. Each entry creates a route at `/<name>` that proxies to the upstream URL.

```hcl
registries = {
  npm  = "https://registry.npmjs.org"
  pypi = "https://pypi.org"
  go   = "https://proxy.golang.org"
}
```

Configure npm to use the firewall:

```bash
npm config set registry https://registry.company.com/npm
```

Configure pip:

```bash
pip install --index-url https://registry.company.com/pypi/simple/ <package>
```

The `domain` variable must match the hostname that clients send in the Host header, and it must be a **single hostname**. The firewall rewrites registry URLs inside npm metadata responses to this value; a value with multiple space-separated tokens produces invalid tarball URLs and breaks `npm install`. If you use a custom DNS name (e.g., `registry.company.com`), set `domain` to that. If you use the Cloud Run URL directly, set `domain` to the hostname portion of the URL from `terraform output service_url` and re-apply.

## Reaching the service

Cloud Run enforces IAM on every request, and package managers cannot attach GCP identity tokens. For real client traffic:

- Set `invoker_members = ["allUsers"]`
- Control reachability with `ingress` and your network instead: `INGRESS_TRAFFIC_INTERNAL_ONLY` limits the service to your VPC (developers reach it over VPN); `INGRESS_TRAFFIC_ALL` exposes the run.app URL, which is acceptable for a short pilot with a small test group

## Outputs

- `service_url` - URL of the deployed Cloud Run service
- `service_name` - Name of the Cloud Run service
- `service_id` - Fully qualified resource ID

## Verify the deployment

For a pilot with `ingress = "INGRESS_TRAFFIC_ALL"` and `invoker_members = ["allUsers"]`, set `domain` to the service hostname from `terraform output service_url`, apply, and test directly:

```bash
URL=$(terraform output -raw service_url)

# Health check — should include "path-routing" in the response
curl -s $URL/health
# Expected: SocketFirewall/x.x.x - Health OK - path-routing (...)

# Test a safe package
npm install lodash --registry $URL/npm

# Test a blocked package
# IMPORTANT: clear npm cache first, or cached tarballs bypass the firewall
npm cache clean --force
npm install peacenotwar@9.1.3 --registry $URL/npm --prefer-online
# Expected: E403 "Blocked by Security Policy"
```

With internal-only ingress, run the same checks from a VM inside the VPC using your custom DNS name. `gcloud run services proxy` is not suitable for verifying package installs: clients reach the proxy as `localhost`, which will not match `domain`, and metadata URL rewriting will not point back at the proxy.

## Troubleshooting

**Container crashes on startup**
Check Cloud Run logs: `gcloud run services logs read socket-registry-firewall --region us-central1 --limit 50`. Common causes: malformed socket.yml, or invalid SSL certificate content when `ssl_cert`/`ssl_key` are set (check `terraform output` to verify secrets were created).

**403 from Cloud Run before reaching the firewall**
The caller is not in `invoker_members`. Package managers cannot authenticate to Cloud Run; grant `allUsers` and restrict reachability with `ingress`.

**404 errors on package requests**
The `domain` variable must match the Host header clients send. If using the Cloud Run URL, extract just the hostname (without `https://`). If using a custom domain, make sure DNS points to the Cloud Run service.

**npm install fails fetching tarballs with invalid URLs**
`domain` contains more than one hostname token. Set it to exactly one hostname and re-apply.

**Packages install but are not scanned**
Verify your API token has the `packages` and `entitlements:list` scopes. With `socket_fail_open = true` (the default), invalid or missing tokens silently pass all packages through without scanning. Check Cloud Run logs for `Firewall access validation failed` or `401` errors.

**Secret Manager version conflicts**
If you change secrets outside Terraform, the next `terraform apply` may show a diff. Run `terraform plan` first to review changes. To force a new secret version, taint the resource: `terraform taint google_secret_manager_secret_version.socket_yml`.

## Notes

Cloud Run mounts secret volumes as directories, not individual files. The template sets the `CONFIG_FILE` env var so the firewall reads `socket.yml` from the correct mounted path. When `ssl_cert`/`ssl_key` are provided, the generated socket.yml references them at `/etc/nginx/ssl/cert/server-cert.pem` and `/etc/nginx/ssl/key/server-key.pem`.

## Other deployment options

- **Already on Kubernetes?** Use the [Helm chart](../../helm)
- **On AWS?** See the [ECS Fargate template](../aws-ecs-fargate) or the [EKS CloudFormation templates](../../cloudformation)
- **On Azure?** See the [Container Apps template](../azure-container-apps)
