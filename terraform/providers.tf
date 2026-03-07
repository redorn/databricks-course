terraform {
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.38"
    }
  }

  # Uncomment to store state in S3 (recommended for team use)
  # backend "s3" {
  #   bucket = "io-lakehouse-terraform-state"
  #   key    = "databricks/raw-ingestion/terraform.tfstate"
  #   region = "eu-west-1"
  # }
}

provider "databricks" {
  host  = var.databricks_host
  token = var.databricks_token
}
