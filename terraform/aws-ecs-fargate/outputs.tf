output "alb_dns_name" {
  description = "DNS name of the ALB (point your registry DNS records here)"
  value       = aws_lb.firewall.dns_name
}

output "alb_zone_id" {
  description = "Route 53 zone ID of the ALB (for alias records)"
  value       = aws_lb.firewall.zone_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.firewall.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.firewall.name
}

output "log_group_name" {
  description = "CloudWatch log group for firewall logs"
  value       = aws_cloudwatch_log_group.firewall.name
}
