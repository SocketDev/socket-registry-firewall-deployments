terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  labels = merge(
    {
      managed-by = "terraform"
      app        = "socket-registry-firewall"
    },
    var.labels,
  )

  use_vpc_connector = var.vpc_connector_name != ""
  use_direct_vpc    = !local.use_vpc_connector && var.vpc_network != ""

  # Bring-your-own SSL cert is optional. Without one, the firewall image's
  # bundled certificate serves the (unused-behind-Cloud-Run) HTTPS listener.
  use_byo_cert = var.ssl_cert != "" && var.ssl_key != ""

  # Service account the revision runs as. Secret volumes and secret env vars
  # are resolved with this identity, so it needs secretAccessor below.
  runtime_service_account = var.service_account != "" ? var.service_account : "${data.google_project.this.number}-compute@developer.gserviceaccount.com"

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
        api_url   = "https://api.socket.dev"
        fail_open = var.socket_fail_open
      }
      cache = {
        ttl = 600
      }
      path_routing = {
        enabled = true
        # Must be a single hostname. Multiple space-separated tokens corrupt
        # the URLs the firewall rewrites into npm metadata responses.
        domain = var.domain
        routes = local.routes
      }
    },
    local.use_byo_cert ? {
      ssl = {
        cert = "/etc/nginx/ssl/cert/server-cert.pem"
        key  = "/etc/nginx/ssl/key/server-key.pem"
      }
    } : {},
    var.webhook_url != "" ? {
      webhook = merge(
        {
          enabled    = true
          url        = var.webhook_url
          on_block   = true
          on_warn    = false
          on_monitor = false
          on_ignore  = false
        },
        var.webhook_auth_header != "" ? { auth_header = var.webhook_auth_header } : {},
      )
    } : {},
  ))
}

# ── Secret Manager secrets ───────────────────────────────────────────

resource "google_secret_manager_secret" "api_token" {
  secret_id = "${var.service_name}-api-token"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_token" {
  secret      = google_secret_manager_secret.api_token.id
  secret_data = var.socket_api_token
}

resource "google_secret_manager_secret" "socket_yml" {
  secret_id = "${var.service_name}-socket-yml"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "socket_yml" {
  secret      = google_secret_manager_secret.socket_yml.id
  secret_data = local.socket_yml
}

resource "google_secret_manager_secret" "ssl_cert" {
  count     = local.use_byo_cert ? 1 : 0
  secret_id = "${var.service_name}-ssl-cert"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ssl_cert" {
  count       = local.use_byo_cert ? 1 : 0
  secret      = google_secret_manager_secret.ssl_cert[0].id
  secret_data = var.ssl_cert
}

resource "google_secret_manager_secret" "ssl_key" {
  count     = local.use_byo_cert ? 1 : 0
  secret_id = "${var.service_name}-ssl-key"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ssl_key" {
  count       = local.use_byo_cert ? 1 : 0
  secret      = google_secret_manager_secret.ssl_key[0].id
  secret_data = var.ssl_key
}

# ── IAM: grant secret access to the identities that resolve them ─────

# google_project_service_identity requires the google-beta provider.
resource "google_project_service_identity" "cloud_run" {
  provider = google-beta
  project  = var.project_id
  service  = "run.googleapis.com"
}

locals {
  secret_ids = concat(
    [
      google_secret_manager_secret.api_token.secret_id,
      google_secret_manager_secret.socket_yml.secret_id,
    ],
    local.use_byo_cert ? [
      google_secret_manager_secret.ssl_cert[0].secret_id,
      google_secret_manager_secret.ssl_key[0].secret_id,
    ] : [],
  )
}

resource "google_secret_manager_secret_iam_member" "cloud_run_access" {
  for_each  = toset(local.secret_ids)
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_project_service_identity.cloud_run.email}"
}

# Secret volumes and secret env vars are resolved with the revision's runtime
# service account. Without this grant, deploys fail in projects that do not
# hand the default compute SA broad legacy roles.
resource "google_secret_manager_secret_iam_member" "runtime_sa_access" {
  for_each  = toset(local.secret_ids)
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runtime_service_account}"
}

# ── Cloud Run v2 service ─────────────────────────────────────────────

resource "google_cloud_run_v2_service" "firewall" {
  name     = var.service_name
  location = var.region
  labels   = local.labels
  ingress  = var.ingress

  template {
    labels          = local.labels
    service_account = var.service_account != "" ? var.service_account : null

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # VPC access: connector or direct
    dynamic "vpc_access" {
      for_each = local.use_vpc_connector || local.use_direct_vpc ? [1] : []
      content {
        dynamic "network_interfaces" {
          for_each = local.use_direct_vpc ? [1] : []
          content {
            network    = var.vpc_network
            subnetwork = var.vpc_subnet
          }
        }
        connector = local.use_vpc_connector ? var.vpc_connector_name : null
        egress    = "ALL_TRAFFIC"
      }
    }

    volumes {
      name = "socket-yml"
      secret {
        secret       = google_secret_manager_secret.socket_yml.secret_id
        default_mode = 292 # 0444
        items {
          version = "latest"
          path    = "socket.yml"
        }
      }
    }

    dynamic "volumes" {
      for_each = local.use_byo_cert ? [1] : []
      content {
        name = "ssl-cert"
        secret {
          secret       = google_secret_manager_secret.ssl_cert[0].secret_id
          default_mode = 292
          items {
            version = "latest"
            path    = "server-cert.pem"
          }
        }
      }
    }

    dynamic "volumes" {
      for_each = local.use_byo_cert ? [1] : []
      content {
        name = "ssl-key"
        secret {
          secret       = google_secret_manager_secret.ssl_key[0].secret_id
          default_mode = 256 # 0400
          items {
            version = "latest"
            path    = "server-key.pem"
          }
        }
      }
    }

    containers {
      image = var.firewall_image

      ports {
        container_port = 8080
        name           = "http1"
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # ── Environment variables ──────────────────────────────────────

      env {
        name = "SOCKET_SECURITY_API_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_token.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "CONFIG_FILE"
        value = "/app/socket-yml/socket.yml"
      }

      env {
        name  = "REDIS_ENABLED"
        value = tostring(var.redis_enabled)
      }

      dynamic "env" {
        for_each = var.redis_enabled ? [1] : []
        content {
          name  = "REDIS_HOST"
          value = var.redis_host
        }
      }

      dynamic "env" {
        for_each = var.redis_enabled ? [1] : []
        content {
          name  = "REDIS_PORT"
          value = tostring(var.redis_port)
        }
      }

      # ── Volume mounts ──────────────────────────────────────────────

      volume_mounts {
        name       = "socket-yml"
        mount_path = "/app/socket-yml"
      }

      dynamic "volume_mounts" {
        for_each = local.use_byo_cert ? [1] : []
        content {
          name       = "ssl-cert"
          mount_path = "/etc/nginx/ssl/cert"
        }
      }

      dynamic "volume_mounts" {
        for_each = local.use_byo_cert ? [1] : []
        content {
          name       = "ssl-key"
          mount_path = "/etc/nginx/ssl/key"
        }
      }

      # ── Health checks ──────────────────────────────────────────────
      # /health is served on the HTTP listener (8080). The TCP startup
      # probe watches the HTTPS listener (8443) purely as a
      # process-is-up signal; Cloud Run only routes traffic to 8080.

      startup_probe {
        tcp_socket {
          port = 8443
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
        timeout_seconds       = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        period_seconds        = 15
        failure_threshold     = 3
        timeout_seconds       = 5
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.cloud_run_access,
    google_secret_manager_secret_iam_member.runtime_sa_access,
  ]
}

# ── IAM: restrict invocation to specified members ────────────────────
# Package managers cannot attach GCP identity tokens, so real client
# traffic needs "allUsers" here, with reachability controlled by the
# ingress setting (and your VPC) rather than by request auth.

resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invoker_members)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.firewall.name
  role     = "roles/run.invoker"
  member   = each.value
}
