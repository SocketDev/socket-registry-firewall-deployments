variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-socket-firewall"
}

variable "environment_name" {
  description = "Name suffix for the Container Apps Environment and related resources"
  type        = string
  default     = "socket-fw"
}

# ── Socket Firewall ──────────────────────────────────────────────────────────

variable "firewall_image" {
  description = "Docker image for the Socket Registry Firewall"
  type        = string
  default     = "socketdev/socket-registry-firewall:latest"
}

variable "socket_api_token" {
  description = "Socket Security API token. Persisted in Terraform state; to avoid that, use socket_api_token_key_vault_secret_id instead."
  type        = string
  sensitive   = true
  default     = ""
}

variable "socket_api_token_key_vault_secret_id" {
  description = "ID of an existing Key Vault secret holding the Socket API token (e.g. https://<vault>.vault.azure.net/secrets/<name>), created out-of-band so the value never passes through Terraform or its state. Takes precedence over socket_api_token. The Container App managed identity needs the Key Vault Secrets User role on that vault."
  type        = string
  default     = ""
}

variable "socket_fail_open" {
  description = "Whether the firewall fails open when Socket API is unreachable"
  type        = bool
  default     = true
}

variable "registries" {
  description = "Map of registry name to upstream URL. Each entry creates a path-based route (e.g., npm = https://registry.npmjs.org creates /npm)."
  type        = map(string)
  default = {
    npm = "https://registry.npmjs.org"
  }
}

variable "domain" {
  description = "Hostname for path-based routing (e.g., registry.company.com). Use the FQDN from the first deploy or your custom DNS name."
  type        = string
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "log_level" {
  description = "Firewall log level: error, warn, info, debug. Debug shows TLS handshakes and full request details in nginx error log."
  type        = string
  default     = "info"

  validation {
    condition     = contains(["error", "warn", "info", "debug"], var.log_level)
    error_message = "log_level must be one of: error, warn, info, debug"
  }
}

variable "debug_logging_enabled" {
  description = "Enable debug logging for HTTP requests and responses"
  type        = bool
  default     = false
}

variable "debug_user_agent_filter" {
  description = "Glob pattern to filter debug logs by user-agent (case-insensitive, e.g. 'pip' or 'npm*')"
  type        = string
  default     = ""
}

# ── Recently Published ────────────────────────────────────────────────────────

variable "recently_published_enabled_ecosystems" {
  description = "List of ecosystems to enforce recently-published package blocking (e.g. [\"npm\", \"pypi\"])"
  type        = list(string)
  default     = []
}

# ── SSL ──────────────────────────────────────────────────────────────────────

variable "generate_self_signed_cert" {
  description = "Generate a self-signed TLS certificate with SANs matching the domain variable. Set to false and provide ssl_cert/ssl_key to use your own certificate."
  type        = bool
  default     = true
}

variable "ssl_cert" {
  description = "PEM-encoded SSL certificate (ignored when generate_self_signed_cert = true)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssl_key" {
  description = "PEM-encoded SSL private key (ignored when generate_self_signed_cert = true)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssl_cert_key_vault_secret_id" {
  description = "ID of an existing Key Vault secret holding the PEM-encoded SSL certificate, created out-of-band. Takes precedence over ssl_cert. Requires generate_self_signed_cert = false."
  type        = string
  default     = ""
}

variable "ssl_key_key_vault_secret_id" {
  description = "ID of an existing Key Vault secret holding the PEM-encoded SSL private key, created out-of-band so the key never passes through Terraform or its state. Takes precedence over ssl_key. Requires generate_self_signed_cert = false."
  type        = string
  default     = ""
}

# ── Redis (optional) ────────────────────────────────────────────────────────

variable "redis_enabled" {
  description = "Enable Redis caching"
  type        = bool
  default     = false
}

variable "redis_host" {
  description = "Redis hostname"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_password" {
  description = "Redis AUTH password (e.g. Azure Cache for Redis access key). Stored in Key Vault and injected as a secret. Note: the value is also persisted in Terraform state; to avoid that, use redis_password_key_vault_secret_id instead."
  type        = string
  default     = ""
  sensitive   = true
}

variable "redis_password_key_vault_secret_id" {
  description = "ID of an existing Key Vault secret holding the Redis password (e.g. https://<vault>.vault.azure.net/secrets/<name>), created out-of-band so the value never passes through Terraform or its state. Takes precedence over redis_password. The Container App managed identity needs the Key Vault Secrets User role on that vault."
  type        = string
  default     = ""
}

variable "redis_ssl" {
  description = "Connect to Redis over TLS. Azure Cache for Redis requires TLS on port 6380."
  type        = bool
  default     = true
}

# ── Scaling ──────────────────────────────────────────────────────────────────

variable "min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 5
}

variable "cpu" {
  description = "CPU cores allocated to the container (e.g. 0.5, 1.0, 2.0)"
  type        = number
  default     = 1.0
}

variable "memory" {
  description = "Memory allocated to the container in Gi (e.g. 1Gi, 2Gi)"
  type        = string
  default     = "2Gi"
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "vnet_id" {
  description = "Resource ID of the VNet for internal networking"
  type        = string
}

variable "subnet_id" {
  description = "Resource ID of the subnet delegated to Container Apps Environment"
  type        = string
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    service    = "socket-registry-firewall"
  }
}
