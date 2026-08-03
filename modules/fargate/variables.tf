variable "name" {}
variable "name_service" {}
variable "vpc_id" {}
variable "image_tag" {
  description = "Tag de la imagen de Docker a desplegar"
  type        = string
  default     = "latest" # Idealmente, tu CI/CD sobreescribirá esto
}