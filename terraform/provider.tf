# provider.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.20"  
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "sa-east-1"  # Región de São Paulo, Brasil
}

provider "random" {
  # Configuración del provider random
}
