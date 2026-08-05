include "root" {
  path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/certificado"
}

inputs  = {
    domain_name    = "telemetria.sediops.site"
}