# Crear repositorio en ECR
resource "aws_ecr_repository" "otel_custom_repo" {
  name                 = "${var.name_service}-otel-collector"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Política para mantener solo las últimas 3 imágenes
resource "aws_ecr_lifecycle_policy" "otel_repo_policy" {
  repository = aws_ecr_repository.otel_custom_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener solo las ultimas 3 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = {
        type = "expire"
      }
    }]
  })
}