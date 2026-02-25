terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  # Partial backend configuration - actual values supplied at init time.
  # Dev:  terraform init                                  (uses local state)
  # Prod: terraform init -backend-config=backend-prod.hcl (uses GCS)
  backend "gcs" {}

  required_providers {
    metabase = {
      source  = "flovouin/metabase"
      version = "~> 0.14"
    }
  }
}