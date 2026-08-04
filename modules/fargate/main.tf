data "aws_secretsmanager_secret" "secrets-dev" {
  name = "secrets-dev"
}

# Decode the secret string if it contains JSON (optional)
#locals {
#  values = jsondecode(data.aws_secretsmanager_secret_version.secrets-dev.secret_string)
#}

resource "aws_ecs_cluster" "fargate_cluster" {
  name = var.name_cluster
}

#Rol de ejecucion para las tareas de ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role-Dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "custom_policy" {
  name = "custom-ecs-execution-policy-Dev"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
Statement = [
      {
        Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:DescribeImages",
            "ecr:DescribeImageScanFindings",
            "ecr:DescribeRepositories",
            "ecr:GetAuthorizationToken",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetLifecyclePolicy",
            "ecr:GetLifecyclePolicyPreview",
            "ecr:GetRepositoryPolicy",
            "ecr:ListImages",
            "ecr:ListTagsForResource",
            "ssm:GetParameters",
            "secretsmanager:GetSecretValue",
            "kms:Decrypt"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
            "logs:GetLogEvents",
            "logs:FilterLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
    }]
  })
  
}

# 1. Security Group para el Balanceador de Carga
resource "aws_security_group" "alb_sg" {
  name        = "${var.name_service}-alb-sg"
  description = "Security group para el ALB del OTel Collector"
  vpc_id      = var.vpc_id

  # Permitir entrada HTTPS desde Internet (Cloudflare apuntará aquí)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    # Opcional (SRE Tip): Para mayor seguridad, puedes restringir esto 
    # únicamente a los rangos de IPs oficiales de Cloudflare.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. El Balanceador de Carga (ALB)
resource "aws_lb" "otel_alb" {
  name               = "${var.name_service}-alb"
  internal           = false # False porque recibirá tráfico desde Internet/Cloudflare
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnets
}

# 3. El Target Group (Apunta al puerto de datos, revisa el puerto de salud)
resource "aws_lb_target_group" "otel_tg" {
  name        = "${var.name_service}-tg"
  port        = 4318      # El tráfico de datos entra por aquí
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    port                = "13133" # ¡La extensión health_check del .yaml!
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# 4. El Listener (Escucha en 443 y manda al Target Group)
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.otel_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # Política moderna recomendada
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otel_tg.arn
  }
}

# Rol para la tarea (puede ser el mismo que el de ejecución para este caso simple)
resource "aws_iam_role" "task_role" {
  name = "ecs-task-role-Dev"

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
}

resource "aws_ecs_task_definition" "fargate_task" {   
    family                   = "fargate-Dev"   
    cpu                      = 256   
    memory                   = 512   
    network_mode             = "awsvpc"   
    requires_compatibilities = ["FARGATE"]
    execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
    container_definitions = jsonencode([
    {
      "name": "aws-otel-collector",
      # AQUI APUNTAMOS AL REPOSITORIO PRIVADO + EL TAG DINÁMICO
      #"image": "${aws_ecr_repository.otel_custom_repo.repository_url}:${var.image_tag}",
      "image": "${var.repository_url}:${var.image_tag}",
      "essential": true,
      "cpu": 128,
      "memory": 256,
      "portMappings": [
        { "containerPort": 4317, "protocol": "tcp" },
        { "containerPort": 4318, "protocol": "tcp" },
        { "containerPort": 2000, "protocol": "udp" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/otel-collector",
          "awslogs-region": "us-east-2",
          "awslogs-stream-prefix": "otel"
        }
      },
      # Ya no necesitamos el "command" porque el Dockerfile 
      # colocará el archivo en la ruta por defecto del collector
      "secrets": [
        {
          "name": "DD_API_KEY",
          "valueFrom": "${data.aws_secretsmanager_secret.secrets-dev.arn}:DD_API_KEY::"
        }
      ],
      "environment": [
        { "name": "DD_SITE", "value": "datadoghq.com" }
      ]
    }
  ])
    
        }

resource "aws_ecs_service" "fargate_service" {   
    name            = var.name_service  
    cluster         = aws_ecs_cluster.fargate_cluster.id
    task_definition = aws_ecs_task_definition.fargate_task.arn   
    desired_count   = 1   
    launch_type      = "FARGATE"   
    network_configuration {     
        subnets          = ["subnet-00a7eb0581a9809e8","subnet-0213a9009720d4d32"]
        security_groups  = [aws_security_group.dev-test.id]
        assign_public_ip = false
        }
    # CONECTAMOS EL SERVICIO AL BALANCEADOR
    load_balancer {
      target_group_arn = aws_lb_target_group.otel_tg.arn
      container_name   = "aws-otel-collector" # Debe coincidir con el name en container_definitions
      container_port   = 4318
    }
}

## Security Group
resource "aws_security_group" "dev-test" {
  name        = "cloudflare-tunnel-sg"
  description = "Security group for Cloudflare tunnel"
  vpc_id      = var.vpc_id # Pasa tu VPC como variable

  # El túnel de Cloudflare solo necesita salida
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Permitir que el ALB le mande métricas al puerto 4318
resource "aws_security_group_rule" "allow_alb_to_ecs_4318" {
  type                     = "ingress"
  from_port                = 4318
  to_port                  = 4318
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.dev-test.id
}

# Permitir que el ALB revise la salud en el puerto 13133
resource "aws_security_group_rule" "allow_alb_to_ecs_health" {
  type                     = "ingress"
  from_port                = 13133
  to_port                  = 13133
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.dev-test.id
}

resource "aws_cloudwatch_log_group" "otel_log_group" {
  name              = "/ecs/otel-collector"
  retention_in_days = 7
}