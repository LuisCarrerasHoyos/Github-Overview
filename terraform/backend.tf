terraform {
  backend "s3" {
    bucket      = "bucket-luiscarreras"
    key         = "wordpress/terraform.tfstate"
    region      = "sa-east-1"
    encrypt     = true
    use_lockfile = true   # Bloqueo local recomendado en Terraform >= 1.5
  }
}
