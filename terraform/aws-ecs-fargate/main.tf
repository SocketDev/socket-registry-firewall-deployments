terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "socket-firewall-${var.environment}"
  common_tags = merge(var.tags, {
    Project     = "socket-firewall"
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # Build path-based routes from the registries map
  routes = [for name, upstream in var.registries : {
    path     = "/${name}"
    upstream = upstream
    registry = name
  }]

  socket_yml = yamlencode({
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
      domain  = "${aws_lb.firewall.dns_name} localhost"
      routes  = local.routes
    }
  })
}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "firewall" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "firewall" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
  tags              = local.common_tags
}

# --- IAM ---

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name_prefix}-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.socket_api_token.arn]
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# --- Secrets Manager ---

resource "aws_secretsmanager_secret" "socket_api_token" {
  name = "${local.name_prefix}/socket-api-token"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "socket_api_token" {
  secret_id     = aws_secretsmanager_secret.socket_api_token.id
  secret_string = var.socket_api_token
}

# --- Security Groups ---

resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = var.vpc_id
  description = "ALB for Socket firewall"

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${local.name_prefix}-ecs-"
  vpc_id      = var.vpc_id
  description = "ECS tasks for Socket firewall"

  ingress {
    description     = "Traffic from ALB"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Health check from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- ALB ---

resource "aws_lb" "firewall" {
  name               = local.name_prefix
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = local.common_tags
}

resource "aws_lb_target_group" "firewall" {
  name        = local.name_prefix
  port        = 8443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "8443"
    protocol            = "HTTPS"
    timeout             = 10
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.firewall.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.firewall.arn
  }
}

# --- ECS Task Definition ---

resource "aws_ecs_task_definition" "firewall" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "socket-firewall"
      image     = var.firewall_image
      essential = true

      entryPoint = ["sh", "-c"]
      command    = ["cat > /app/socket.yml << 'SOCKETCFG'\n${local.socket_yml}\nSOCKETCFG\nexec /usr/local/bin/entrypoint.sh"]

      portMappings = [
        { containerPort = 8080, protocol = "tcp" },
        { containerPort = 8443, protocol = "tcp" }
      ]

      environment = concat(
        [],
        var.redis_enabled ? [
          { name = "REDIS_ENABLED", value = "true" },
          { name = "REDIS_HOST", value = var.redis_host },
          { name = "REDIS_PORT", value = tostring(var.redis_port) }
        ] : []
      )

      secrets = [
        {
          name      = "SOCKET_SECURITY_API_TOKEN"
          valueFrom = aws_secretsmanager_secret.socket_api_token.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.firewall.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "firewall"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -fk https://localhost:8443/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = local.common_tags
}

# --- ECS Service ---

resource "aws_ecs_service" "firewall" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.firewall.id
  task_definition = aws_ecs_task_definition.firewall.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.firewall.arn
    container_name   = "socket-firewall"
    container_port   = 8443
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags
}

# --- Auto Scaling ---

resource "aws_appautoscaling_target" "firewall" {
  max_capacity       = var.desired_count * 4
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.firewall.name}/${aws_ecs_service.firewall.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "firewall_cpu" {
  name               = "${local.name_prefix}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.firewall.resource_id
  scalable_dimension = aws_appautoscaling_target.firewall.scalable_dimension
  service_namespace  = aws_appautoscaling_target.firewall.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
