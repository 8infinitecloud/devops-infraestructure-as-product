terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "aurex-infrastructure-as-a-product"
      Demo    = "demo2-hcp-terraform-engine"
    }
  }
}
