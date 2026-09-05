terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    pkcs12 = {
      source  = "chilicat/pkcs12"
      version = "~> 0.2"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  env_name = var.environment_name

  # Direct routes: /npm -> https://registry.npmjs.org
  # For Artifactory (upstream mode), use /repository/<repo-name> paths instead:
  #   registries = {
  #     "repository/npm-remote" = "https://company.jfrog.io/artifactory/api/npm/npm-remote"
  #   }
  # This creates a route at /repository/npm-remote that proxies to your Artifactory
  # virtual or remote repository. Configure npm with:
  #   npm config set registry https://<FQDN>/repository/npm-remote

  routes = [for name, upstream in var.registries : {
    path     = "/${name}"
    upstream = upstream
    registry = name
  }]

  socket_yml = yamlencode(merge(
    {
      ports = {
        http  = 8080
        https = 8443
      }
      socket = {
        fail_open = var.socket_fail_open
      }
      cache = {
        ttl = 600
      }
      ssl = {
        cert = "/mnt/config/ssl-cert"
        key  = "/mnt/config/ssl-key"
      }
      path_routing = {
        enabled = true
        domain  = "${var.domain} localhost"
        routes  = local.routes
      }
    },
    var.debug_logging_enabled ? {
      debug = merge(
        { logging_enabled = true },
        var.debug_user_agent_filter != "" ? { user_agent_filter = var.debug_user_agent_filter } : {}
      )
    } : {},
    length(var.recently_published_enabled_ecosystems) > 0 ? {
      recently_published_enabled_ecosystems = var.recently_published_enabled_ecosystems
    } : {}
  ))
}

# ── Resource Group ───────────────────────────────────────────────────────────

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Log Analytics ────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.env_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ── Managed Identity ─────────────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${local.env_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

# ── Key Vault ────────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "this" {
  name                       = "kv-${local.env_name}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true
  tags                       = var.tags
}

# Grant the managed identity access to read secrets
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# Grant the deploying principal access to write secrets
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Only created when the token is passed directly. With
# socket_api_token_key_vault_secret_id, the secret is managed out-of-band and
# the value never enters Terraform or its state.
resource "azurerm_key_vault_secret" "socket_api_token" {
  count        = var.socket_api_token != "" && var.socket_api_token_key_vault_secret_id == "" ? 1 : 0
  name         = "socket-api-token"
  value        = var.socket_api_token
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer]
}

# Preserve existing deployments now that the secret resources use count
moved {
  from = azurerm_key_vault_secret.socket_api_token
  to   = azurerm_key_vault_secret.socket_api_token[0]
}

locals {
  socket_api_token_secret_id = var.socket_api_token_key_vault_secret_id != "" ? var.socket_api_token_key_vault_secret_id : (var.socket_api_token != "" ? azurerm_key_vault_secret.socket_api_token[0].versionless_id : "")
}

# Only created when the password is passed directly. With
# redis_password_key_vault_secret_id, the secret is managed out-of-band and
# the value never enters Terraform or its state.
resource "azurerm_key_vault_secret" "redis_password" {
  count        = var.redis_password != "" && var.redis_password_key_vault_secret_id == "" ? 1 : 0
  name         = "redis-password"
  value        = var.redis_password
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer]
}

locals {
  redis_password_secret_id = var.redis_password_key_vault_secret_id != "" ? var.redis_password_key_vault_secret_id : (var.redis_password != "" ? azurerm_key_vault_secret.redis_password[0].versionless_id : "")
}

# ── Self-signed TLS certificate (optional) ──────────────────────────────────
# When generate_self_signed_cert = true, creates a server cert with SANs matching
# the domain variable. This covers common setups where the firewall sits behind
# a load balancer (Azure Front Door, Application Gateway, etc.) that terminates
# the public TLS and re-encrypts to the Container App.
#
# For Front Door with private link + certificate subject name validation, the
# cert must include a SAN matching the origin host header. Add extra hostnames
# (e.g., the Front Door endpoint FQDN) to the domain variable separated by spaces.

resource "tls_private_key" "server" {
  count     = var.generate_self_signed_cert ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "server" {
  count           = var.generate_self_signed_cert ? 1 : 0
  private_key_pem = tls_private_key.server[0].private_key_pem

  subject {
    common_name  = split(" ", var.domain)[0]
    organization = "Socket Firewall (${local.env_name})"
  }

  # Include all space-separated hostnames from the domain variable as SANs,
  # plus "localhost" for in-container testing.
  dns_names = concat(
    [for d in split(" ", var.domain) : d if d != "localhost"],
    ["localhost"]
  )

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = false

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "pkcs12_from_pem" "server" {
  count           = var.generate_self_signed_cert ? 1 : 0
  cert_pem        = tls_self_signed_cert.server[0].cert_pem
  private_key_pem = tls_private_key.server[0].private_key_pem
  password        = ""
}

locals {
  ssl_cert_pem = var.generate_self_signed_cert ? tls_self_signed_cert.server[0].cert_pem : var.ssl_cert
  ssl_key_pem  = var.generate_self_signed_cert ? tls_private_key.server[0].private_key_pem : var.ssl_key

  # Custom domains: all hostnames from the domain variable except "localhost"
  custom_domains = [for d in split(" ", var.domain) : d if d != "localhost"]
}

resource "azurerm_key_vault_secret" "ssl_cert" {
  count        = var.ssl_cert_key_vault_secret_id == "" ? 1 : 0
  name         = "ssl-cert"
  value        = local.ssl_cert_pem
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "ssl_key" {
  count        = var.ssl_key_key_vault_secret_id == "" ? 1 : 0
  name         = "ssl-key"
  value        = local.ssl_key_pem
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer]
}

# Preserve existing deployments now that the secret resources use count
moved {
  from = azurerm_key_vault_secret.ssl_cert
  to   = azurerm_key_vault_secret.ssl_cert[0]
}

moved {
  from = azurerm_key_vault_secret.ssl_key
  to   = azurerm_key_vault_secret.ssl_key[0]
}

locals {
  ssl_cert_secret_id = var.ssl_cert_key_vault_secret_id != "" ? var.ssl_cert_key_vault_secret_id : azurerm_key_vault_secret.ssl_cert[0].versionless_id
  ssl_key_secret_id  = var.ssl_key_key_vault_secret_id != "" ? var.ssl_key_key_vault_secret_id : azurerm_key_vault_secret.ssl_key[0].versionless_id
}

# ── Container Apps Environment ───────────────────────────────────────────────

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${local.env_name}"
  location                       = azurerm_resource_group.this.location
  resource_group_name            = azurerm_resource_group.this.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = true
  tags                           = var.tags

  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
}

# ── Custom Domain + Certificate Binding ──────────────────────────────────────
# Registers the TLS certificate with the Container Apps Environment and binds
# each custom domain (from the domain variable) to the Container App.
# Without this, the Container Apps ingress rejects requests with Host headers
# that don't match the default FQDN, returning 404 before nginx ever sees them.
# This is required when Azure Front Door sends the custom domain as the origin
# host header (which it must, so tarball URLs are rewritten correctly).

resource "azurerm_container_app_environment_certificate" "server" {
  count                        = var.generate_self_signed_cert ? 1 : 0
  name                         = "cert-${local.env_name}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  certificate_blob_base64      = pkcs12_from_pem.server[0].result
  certificate_password         = ""
}

# ── Container App ────────────────────────────────────────────────────────────

resource "azurerm_container_app" "firewall" {
  name                         = "ca-${local.env_name}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  lifecycle {
    precondition {
      condition     = var.socket_api_token != "" || var.socket_api_token_key_vault_secret_id != ""
      error_message = "Set socket_api_token or socket_api_token_key_vault_secret_id."
    }
    precondition {
      condition     = !(var.generate_self_signed_cert && (var.ssl_cert_key_vault_secret_id != "" || var.ssl_key_key_vault_secret_id != ""))
      error_message = "ssl_cert_key_vault_secret_id and ssl_key_key_vault_secret_id require generate_self_signed_cert = false."
    }
  }

  # ── Secrets (pulled from Key Vault via managed identity) ─────────────────

  secret {
    name                = "socket-api-token"
    key_vault_secret_id = local.socket_api_token_secret_id
    identity            = azurerm_user_assigned_identity.this.id
  }

  secret {
    name                = "ssl-cert"
    key_vault_secret_id = local.ssl_cert_secret_id
    identity            = azurerm_user_assigned_identity.this.id
  }

  secret {
    name                = "ssl-key"
    key_vault_secret_id = local.ssl_key_secret_id
    identity            = azurerm_user_assigned_identity.this.id
  }

  secret {
    name  = "socket-yml"
    value = local.socket_yml
  }

  dynamic "secret" {
    for_each = local.redis_password_secret_id != "" ? [1] : []
    content {
      name                = "redis-password"
      key_vault_secret_id = local.redis_password_secret_id
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  # ── Ingress (internal only) ─────────────────────────────────────────────

  ingress {
    # On an internal environment (internal_load_balancer_enabled = true),
    # external_enabled = true scopes ingress to the VNet (portal shows
    # "Limited to VNet"). Setting it to false scopes ingress to the Container
    # Apps environment only, which leaves the firewall unreachable from
    # developer machines, CI runners, jumpboxes, or Front Door.
    external_enabled = true

    # 8080 is the plaintext listener (see ports.http in socket_yml above).
    # TLS is terminated by Container Apps ingress, so target_port must match
    # transport. Pointing "http" transport at 8443 sends cleartext to the
    # TLS listener: the revision passes its health probes and serves nothing.
    target_port = 8080
    transport   = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # ── Template ────────────────────────────────────────────────────────────

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Volume: secrets projected as files
    volume {
      name         = "config"
      storage_type = "Secret"
    }

    container {
      name   = "socket-registry-firewall"
      image  = var.firewall_image
      cpu    = var.cpu
      memory = var.memory

      # ── Environment variables ──────────────────────────────────────────

      env {
        name        = "SOCKET_SECURITY_API_TOKEN"
        secret_name = "socket-api-token"
      }

      env {
        name  = "CONFIG_FILE"
        value = "/mnt/config/socket-yml"
      }

      env {
        name  = "REDIS_ENABLED"
        value = tostring(var.redis_enabled)
      }

      env {
        name  = "REDIS_HOST"
        value = var.redis_host
      }

      env {
        name  = "REDIS_PORT"
        value = tostring(var.redis_port)
      }

      dynamic "env" {
        for_each = local.redis_password_secret_id != "" ? [1] : []
        content {
          name        = "REDIS_PASSWORD"
          secret_name = "redis-password"
        }
      }

      env {
        name  = "REDIS_SSL"
        value = tostring(var.redis_ssl)
      }

      # Firewall behavior env vars (must be set as env vars, not just in socket.yml)
      env {
        name  = "SOCKET_FAIL_OPEN"
        value = tostring(var.socket_fail_open)
      }

      env {
        name  = "SOCKET_LOG_LEVEL"
        value = var.log_level
      }

      env {
        name  = "SOCKET_DEBUG_LOGGING_ENABLED"
        value = tostring(var.debug_logging_enabled)
      }

      env {
        name  = "SOCKET_DEBUG_USER_AGENT_FILTER"
        value = var.debug_user_agent_filter
      }

      # ── Volume mounts ─────────────────────────────────────────────────
      # Secret volumes project each secret as a file named after the secret.
      # The container's entrypoint or an init script should copy/symlink:
      #   /mnt/config/socket-yml       -> /app/socket.yml
      #   /mnt/config/ssl-cert         -> /etc/nginx/ssl/server-cert.pem
      #   /mnt/config/ssl-key          -> /etc/nginx/ssl/server-key.pem

      volume_mounts {
        name = "config"
        path = "/mnt/config"
      }

      # ── Liveness probe ────────────────────────────────────────────────

      liveness_probe {
        transport               = "HTTPS"
        port                    = 8443
        path                    = "/health"
        initial_delay           = 15
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      # ── Readiness probe ───────────────────────────────────────────────

      readiness_probe {
        transport               = "HTTPS"
        port                    = 8443
        path                    = "/health"
        interval_seconds        = 10
        timeout                 = 3
        failure_count_threshold = 3
        success_count_threshold = 1
      }

      # ── Startup probe ─────────────────────────────────────────────────

      startup_probe {
        transport               = "HTTPS"
        port                    = 8443
        path                    = "/health"
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 10
      }
    }

    # ── Scaling rule (CPU-based) ──────────────────────────────────────────

    custom_scale_rule {
      name             = "cpu-scaling"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"
        value = "70"
      }
    }
  }
}

# ── Custom Domain Bindings ─────────────────────────────────────────────────
# Bind each custom domain to the Container App so the ingress accepts requests
# with those Host headers. Without this, Front Door gets 404 when it sends
# Host: <custom-domain> to the Container App.

resource "azurerm_container_app_custom_domain" "domains" {
  for_each = var.generate_self_signed_cert ? toset(local.custom_domains) : toset([])

  name                                     = each.value
  container_app_id                         = azurerm_container_app.firewall.id
  container_app_environment_certificate_id = azurerm_container_app_environment_certificate.server[0].id
  certificate_binding_type                 = "SniEnabled"
}
