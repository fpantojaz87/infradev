include "root" {
  path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/fargate"
}

inputs  = {
    name_cluster   = "dev-fargate-cluster"
    vpc_id         = "vpc-0db2b799b439af1be"
    
    # Pasamos la URL dinámicamente
    repository_url = "074925397305.dkr.ecr.us-east-2.amazonaws.com/otel-collector-otel-collector"
    
    # Usamos "latest" porque así etiquetamos la imagen en el paso de Docker
    image_tag      = "latest"
    name_service  = "otel-collector"
    acm_certificate_arn = "arn:aws:acm:us-east-2:074925397305:certificate/edd2e87c-7496-4b24-9da5-705359f20ebc"
    public_subnets = ["subnet-0150d27403f85026b", "subnet-0c61024caa59b79df"]
}