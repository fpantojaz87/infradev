#data "aws_secretsmanager_secret_version" "secrets-privalia2" {
#  secret_id = "secrets-privalia2"
#}

# Decode the secret string if it contains JSON (optional)
#locals {
#  values = jsondecode(data.aws_secretsmanager_secret_version.secrets-privalia2.secret_string)
#}

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
            "ecr:ListTagsForResource"
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
      "image": "${aws_ecr_repository.otel_custom_repo.repository_url}:${var.image_tag}",
      "essential": true,
      "cpu": 256,
      "memory": 512,
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
          "valueFrom": "dd-api-key-secret-arn" # Asegúrate de que el rol de ejecución tenga permisos de lectura en Secrets Manager para este ARN
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
    cluster         = "fagate-Dev"  
    task_definition = aws_ecs_task_definition.fargate_task.arn   
    desired_count   = 1   
    launch_type      = "FARGATE"   
    network_configuration {     
        subnets          = ["subnet-0fefd8a751e03da2a","subnet-0ee8c736f048a4482","subnet-0f22d771a4660b226"]
        security_groups  = [aws_security_group.dev-test.id]
        assign_public_ip = false
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