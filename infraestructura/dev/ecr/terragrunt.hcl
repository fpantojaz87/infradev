include "root" {
  path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/ecr"
}

inputs  = {
    name = "otel-collector"
    name_service = "otel-collector"
    vpc_id = "vpc-0db2b799b439af1be"
}