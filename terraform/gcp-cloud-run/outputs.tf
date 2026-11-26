output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.firewall.uri
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.firewall.name
}

output "service_id" {
  description = "Fully qualified resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.firewall.id
}
