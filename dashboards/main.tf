terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  backend "gcs" {
    bucket = "mfb-terraform-state"
    prefix = "dashboards"
  }

  required_providers {
    metabase = {
      source  = "flovouin/metabase"
      version = "~> 0.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}