# 1. Solicitamos el certificado gratuito a AWS
resource "aws_acm_certificate" "otel_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Le decimos a Terraform que espere a que el certificado esté validado
resource "aws_acm_certificate_validation" "otel_cert_validation" {
  certificate_arn         = aws_acm_certificate.otel_cert.arn
  
  # Extraemos el nombre del registro que AWS espera, sin depender de Route53
  validation_record_fqdns = [for dvo in aws_acm_certificate.otel_cert.domain_validation_options : dvo.resource_record_name]
}