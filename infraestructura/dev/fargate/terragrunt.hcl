include "root" {
  path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/fargate"
}

# 1. Declaramos la dependencia hacia el módulo ECR
dependency "ecr" {
  config_path = "../ecr"
  
  # Mock para que comandos como 'terragrunt plan' funcionen si el ECR aún no existe
  mock_outputs = {
    repository_url = "123456789012.dkr.ecr.us-east-2.amazonaws.com/mock-repo"
  }
}

inputs  = {
    name_cluster = "dev-fargate-cluster"
    vpc_id = "vpc-0db2b799b439af1be"
}

# 2. Pasamos la URL dinámicamente desde el output del módulo ECR
  repository_url = dependency.ecr.outputs.repository_url
  image_tag      = "v1" # O el tag que corresponda
}