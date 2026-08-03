remote_state {
    backend = "s3"
    generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
    config = {
        bucket  = "tf-iac-otel"
        key = "${path_relative_to_include()}/terraform.tfstate"
        region  = "us-east-2"
        encrypt = true
        use_lockfile = true
    }
}

generate "provider" {
    path    = "provider.tf"
    if_exists = "overwrite"
    contents = <<EOF
    provider "aws" {
    region = "us-east-2"
    }
    EOF
}