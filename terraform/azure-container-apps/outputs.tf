output "fqdn" {
  description = "Internal FQDN of the Socket Registry Firewall container app"
  value       = azurerm_container_app.firewall.ingress[0].fqdn
}

output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.this.name
}

output "container_app_name" {
  description = "Name of the Container App running the firewall"
  value       = azurerm_container_app.firewall.name
}

output "container_app_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.this.name
}

output "key_vault_name" {
  description = "Name of the Key Vault storing secrets"
  value       = azurerm_key_vault.this.name
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "ssl_cert_sans" {
  description = "Subject Alternative Names on the SSL certificate (for verifying Front Door cert validation)"
  value       = var.generate_self_signed_cert ? tls_self_signed_cert.server[0].dns_names : ["(using provided cert)"]
}

output "troubleshooting" {
  description = "Useful commands for debugging the firewall deployment"
  value       = <<-EOT

    # ── View container logs (real-time) ──────────────────────────────
    az containerapp logs show -n ${azurerm_container_app.firewall.name} -g ${azurerm_resource_group.this.name} --type console --follow

    # ── Force a new revision (picks up new secrets/env vars) ─────────
    az containerapp update -n ${azurerm_container_app.firewall.name} -g ${azurerm_resource_group.this.name}

    # ── Open a console session ───────────────────────────────────────
    az containerapp exec -n ${azurerm_container_app.firewall.name} -g ${azurerm_resource_group.this.name}

    # ── Verify cert SANs inside container ────────────────────────────
    # (run from console)
    openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -subject -ext subjectAltName

    # ── Check nginx config ───────────────────────────────────────────
    # (run from console)
    grep server_name /app/sites-enabled/path-routing.conf
    cat /app/nginx.conf | grep error_log

    # ── Test health endpoint from inside container ───────────────────
    # (run from console)
    curl -sk https://localhost:8443/health

    # ── Test npm route from inside container ─────────────────────────
    # (run from console)
    curl -sk https://localhost:8443/npm/lodash | head -c 200

    # ── Check tarball URL rewriting ──────────────────────────────────
    # (run from console) Tarball URLs should use your domain, not the Container App FQDN
    curl -sk https://localhost:8443/npm/lodash | grep -o '"tarball":"[^"]*"' | head -3

  EOT
}
