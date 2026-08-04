#variable "name" {}
variable "name_service" {}
variable "vpc_id" {}
variable "name_cluster" {}
variable "repository_url" {
  description = "URL del repositorio ECR donde está la imagen de Docker"
  type        = string
}
variable "image_tag" {
  description = "Tag de la imagen de Docker a desplegar"
  type        = string
  default     = "latest" # Idealmente, tu CI/CD sobreescribirá esto
}

variable "public_subnets" {
  description = "Lista de subredes públicas para el ALB"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ARN del certificado SSL en AWS Certificate Manager"
  type        = string
}