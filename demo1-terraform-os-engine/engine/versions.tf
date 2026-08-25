terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "aurex-infrastructure-as-a-product"
      Demo    = "demo1-terraform-os-engine"
    }
  }
}
