variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run deployment"
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "socket-registry-firewall"
}

variable "firewall_image" {
  description = "Docker image for the Socket Registry Firewall"
  type        = string
  default     = "socketdev/socket-registry-firewall:latest"
}

# ── Secrets ──────────────────────────────────────────────────────────

variable "socket_api_token" {
  description = "Socket Security API token"
  type        = string
  sensitive   = true
}

variable "ssl_cert" {
  description = "PEM-encoded SSL certificate for the firewall's HTTPS listener. Optional behind Cloud Run, which terminates TLS before the container; leave empty to use the image's bundled certificate."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssl_key" {
  description = "PEM-encoded SSL private key. Optional; see ssl_cert."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Firewall config ─────────────────────────────────────────────────

variable "registries" {
  description = "Map of registry name to upstream URL. Each entry creates a path-based route (e.g., npm = https://registry.npmjs.org creates /npm)."
  type        = map(string)
  default = {
    npm = "https://registry.npmjs.org"
  }
}

variable "domain" {
  description = "Hostname clients use to reach the firewall (e.g., registry.company.com, or the Cloud Run URL's hostname after the first deploy). Must be a single hostname; the firewall rewrites registry URLs in npm metadata to this value, and extra tokens produce invalid URLs."
  type        = string

  validation {
    condition     = !can(regex("\\s", var.domain))
    error_message = "domain must be a single hostname with no whitespace."
  }
}

variable "socket_fail_open" {
  description = "If true, allow requests when Socket API is unreachable"
  type        = bool
  default     = true
}

variable "webhook_url" {
  description = "Optional HTTPS endpoint that receives a JSON event for each blocked package decision (for SIEM or chat alerting). Leave empty to disable."
  type        = string
  default     = ""
}

variable "webhook_auth_header" {
  description = "Optional Authorization header value sent with webhook events"
  type        = string
  sensitive   = true
  default     = ""
}

# ── Redis ────────────────────────────────────────────────────────────

variable "redis_enabled" {
  description = "Enable Redis caching. Recommended when running more than one instance so verdict lookups stay consistent."
  type        = bool
  default     = false
}

variable "redis_host" {
  description = "Redis host address"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# ── Scaling & resources ─────────────────────────────────────────────

variable "min_instances" {
  description = "Minimum number of Cloud Run instances. Production deployments run at least 3; see the sizing guide for counts by developer count."
  type        = number
  default     = 3
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU allocation per instance ('1', '2', '4', or '8'). '4' with '8Gi' matches the sizing guide; the nginx worker count follows this value."
  type        = string
  default     = "4"
}

variable "memory" {
  description = "Memory allocation per instance (e.g. '8Gi'). Metadata filtering needs about 2Gi per CPU."
  type        = string
  default     = "8Gi"
}

# ── Networking ───────────────────────────────────────────────────────

variable "ingress" {
  description = "Cloud Run ingress setting. INGRESS_TRAFFIC_INTERNAL_ONLY for production behind a VPC; INGRESS_TRAFFIC_ALL is useful for a short pilot when the test group is not on the VPC."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.ingress)
    error_message = "ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "vpc_network" {
  description = "VPC network name or self_link for Direct VPC egress"
  type        = string
  default     = ""
}

variable "vpc_subnet" {
  description = "Subnet name or self_link for Direct VPC egress"
  type        = string
  default     = ""
}

variable "vpc_connector_name" {
  description = "Serverless VPC Access connector name (full resource path). If set, used instead of Direct VPC egress."
  type        = string
  default     = ""
}

# ── Access ───────────────────────────────────────────────────────────

variable "service_account" {
  description = "Email of the service account the Cloud Run revision runs as. Empty uses the project's default compute service account. Secrets access is granted to whichever identity is used."
  type        = string
  default     = ""
}

variable "invoker_members" {
  description = "IAM members allowed to invoke the service. Package managers cannot send GCP identity tokens, so client traffic requires [\"allUsers\"], with reachability controlled by the ingress setting and your network."
  type        = list(string)
  default     = []
}

# ── Labels ───────────────────────────────────────────────────────────

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}
