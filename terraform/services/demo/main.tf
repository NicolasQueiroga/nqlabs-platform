module "demo" {
  source    = "../../modules/nqlabs-service"
  name      = "demo"
  apps_root = "${path.module}/../../../apps"

  environments = {
    staging = {
      image_repository = "ghcr.io/nicolasqueiroga/nqlabs-demo"
      image_tag        = "sha-e742e7897a80"
    }

    production = {
      image_repository = "ghcr.io/nicolasqueiroga/nqlabs-demo"
      image_tag        = "sha-aec3a454e4aa"
    }
  }
}
