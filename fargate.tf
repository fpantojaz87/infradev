resource "aws_ecs_cluster" "fargate_cluster" {
  name = "fargate-repep-cluster"
}

#Rol de ejecucion para las tareas de ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role-repep"

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

# Rol para la tarea (puede ser el mismo que el de ejecución para este caso simple)
resource "aws_iam_role" "task_role" {
  name = "ecs-task-role"

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

# Rol para EventBridge Scheduler
resource "aws_iam_role" "scheduler_role" {
  name = "eventbridge-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "scheduler_policy" {
  name        = "eventbridge-scheduler-policy"
  description = "Permisos para ejecutar tareas ECS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:RunTask"
        ],
        Resource = [aws_ecs_task_definition.fargate_task_etl.arn]
      },
      {
        Effect = "Allow",
        Action = [
          "iam:PassRole"
        ],
        Resource = [
          aws_iam_role.ecs_task_execution_role.arn,
          aws_iam_role.task_role.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeTasks"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "scheduler_policy_attachment" {
  role       = aws_iam_role.scheduler_role.name
  policy_arn = aws_iam_policy.scheduler_policy.arn
}


## Schedule con EventBridge Scheduler
resource "aws_scheduler_schedule" "cron_etl" {
  name       = "run-cron-etl"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(28 15 * * ? *)" # cambiar ejecucion a las 9 am 

  target {
    arn      = aws_ecs_cluster.fargate_cluster.arn
    role_arn = aws_iam_role.scheduler_role.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.fargate_task_etl.arn
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        assign_public_ip = false
        security_groups  = ["sg-08ee2ceb4eee4e7cc"]
        subnets          = ["subnet-083a293f456533d3b"] # Reemplaza con tus subnets privadas
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = 300 # 24 horas
      maximum_retry_attempts       = 1
    }
  }
}

# Create the secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "repep_secret" {
  name        = "repep-secret"
  description = "Almacena las credenciales usadas en el proyecto repep en los contenedores de fargate."
}

# Retrieve the latest version of the secret value
data "aws_secretsmanager_secret_version" "repep_version" {
  secret_id = aws_secretsmanager_secret.repep_secret.id
}

# Decode the secret string if it contains JSON (optional)
locals {
  secret_data = jsondecode(data.aws_secretsmanager_secret_version.repep_version.secret_string)
}

variable "backend_vars" {
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    { name = "app.base-url", value = "http://app3-front.agile-qk.com" },
    { name = "server.port", value = "8080" },
    { name = "HIBERNATE_DDL_AUTO", value = "none" },
    #{ name = "MYSQL_SERVER_SCHEMA", value = "repep" },
    { name = "spring.jpa.hibernate.ddl-auto", value = "none" },
    { name = "BPL_JVM_THREAD_COUNT", value = "15"},
    { name = "BPL_JVM_THREAD_STACK_SIZE", value = "512k" },
    { name = "BPL_JVM_HEAD_ROOM", value = "10"}
  ]
}

variable "etl_vars" {
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    { name = "MYSQL_SERVER_DATABASE", value = "repep" },
    { name = "MYSQL_SERVER_SCHEMA", value = "repep" },
    { name = "EMAIL_ERRORMESSAGE", value = "Hubo un problema con la ejecución del proceso pentaho." },
    { name = "EMAIL_MESSAGE", value = "Se ejecutó el proceso de carga de listas REPEP de forma exitosa." },
    { name = "EMAIL_NAME", value = "INFO" },
    { name = "EMAIL_PORT", value = "587" },
    { name = "MAIL_SUBJECT", value = "Resultado de ejecución de Pentaho" },
    { name = "TZ", value = "America/Mexico_City" }
  ]
}

#Definicion para la tarea de los contenedores

resource "aws_ecs_task_definition" "fargate_task" {
  family                   = "fargate-repep-task"
  cpu                      = 1024
  memory                   = 4096
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name      = "backend-container",
      image     = "qkcontenedores/axo-repep-backend:1.0.18",
      memory    = 4000,
      essential = true,
      environment = concat(var.backend_vars, [
        #{ name = "MYSQL_PASSWORD", value = local.secret_data["MYSQL_PASSWORD"] },
        #{ name = "MYSQL_SERVER_URL", value = module.aurora_mysql_v2.cluster_endpoint },
        #{ name = "MYSQL_USER", value = local.secret_data["MYSQL_USER"] },
        { name = "EMAIL_PASSWORD", value = local.secret_data["EMAIL_PASSWORD"] },
        { name = "EMAIL_USER", value = local.secret_data["EMAIL_USER"] },
        { name = "spring.datasource.url", value = local.secret_data["spring.datasource.url"]}
      ])
      portMappings = [
        {
          containerPort = 8080,
          hostPort      = 8080,
          protocol      = "tcp"
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/fargate-repep-task",
          "awslogs-region"        = "us-east-1",
          "awslogs-stream-prefix" = "ecs-backend"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "fargate_task_etl" {
  family                   = "fargate-repep-task-etl"
  cpu                      = 2048
  memory                   = 8192
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name      = "delta-etl-container",
      image     = "qkcontenedores/axo-repep-delta-etl:1.0.5",
      environment = concat(var.etl_vars, [
        { name = "MYSQL_SERVER_URL", value = module.aurora_mysql_v2.cluster_endpoint },
        { name = "MYSQL_SERVER_PORT", value = "3306" },
        { name = "MYSQL_USER", value = local.secret_data["MYSQL_USER"] },
        { name = "MYSQL_PASSWORD", value = local.secret_data["MYSQL_PASSWORD"] },
        { name = "EMAIL_CC", value = local.secret_data["EMAIL_CC"] },
        { name = "EMAIL_DEST", value = local.secret_data["EMAIL_DEST"] },
        { name = "EMAIL_NAME", value = local.secret_data["EMAIL_NAME"] },
        { name = "EMAIL_HOST", value = local.secret_data["EMAIL_HOST"] },
        { name = "EMAIL_LASTNAME", value = local.secret_data["EMAIL_LASTNAME"] },
        { name = "EMAIL_PASSWORD", value = local.secret_data["EMAIL_PASSWORD"] },
        { name = "EMAIL_USER", value = local.secret_data["EMAIL_USER"] },
        { name = "AWS_SECRET_KEY", value = local.secret_data["AWS_SECRET_KEY"] },
        { name = "AWS_ACCESS_KEY", value = local.secret_data["AWS_ACCESS_KEY"] }
      ])
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/fargate-repep-task",
          "awslogs-region"        = "us-east-1", # Cambia según tu región
          "awslogs-stream-prefix" = "ecs-etl"
        }
      }
    }
  ])
}

###Tests para cron


#Grupo de logs para los contenedores
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/fargate-repep-task"
  retention_in_days = 3
}


resource "aws_ecs_service" "fargate_service" {
  name            = "fargate-repep-service"
  cluster         = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.fargate_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [module.security-group.security_group_id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "backend-container"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.http_listener]
}
# Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb-repep"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security-group.security_group_id]
  subnets            = module.vpc.public_subnets
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name        = "app-tg-repep"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/actuator"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

# Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}