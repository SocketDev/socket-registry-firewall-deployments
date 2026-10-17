variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g. production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID where the firewall will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "socket_api_token" {
  description = "Socket.dev API token (scopes: packages, entitlements:list)"
  type        = string
  sensitive   = true
}

variable "socket_fail_open" {
  description = "Whether to fail open when Socket API is unavailable"
  type        = bool
  default     = true
}

variable "registries" {
  description = "Map of registries to proxy. Key is the registry name (npm, pypi, maven, etc.), value is the upstream URL. Each entry creates a path-based route (e.g., /npm, /pypi)."
  type        = map(string)
  default = {
    npm = "https://registry.npmjs.org"
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener"
  type        = string
}

variable "firewall_image" {
  description = "Docker image for the Socket firewall"
  type        = string
  default     = "socketdev/socket-registry-firewall:latest"
}

variable "desired_count" {
  description = "Number of ECS tasks to run, and the autoscaling minimum. Production deployments run at least 3; see the sizing guide for counts by developer count."
  type        = number
  default     = 3
}

variable "cpu" {
  description = "CPU units for the ECS task (1024 = 1 vCPU). 4096 with 8192 MB matches the sizing guide; the nginx worker count follows this value."
  type        = number
  default     = 4096
}

variable "memory" {
  description = "Memory in MB for the ECS task. Metadata filtering needs about 2048 MB per vCPU."
  type        = number
  default     = 8192
}

variable "redis_enabled" {
  description = "Enable Redis caching for Socket API responses"
  type        = bool
  default     = false
}

variable "redis_host" {
  description = "Redis host (only used if redis_enabled is true)"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks (required if using public subnets without NAT gateway)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
