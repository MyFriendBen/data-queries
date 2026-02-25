terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  # No backend block here — Terraform defaults to local state for dev.
  # For production, copy backend.tf.example to backend.tf (gitignored) before
  # running terraform init. See README "Terraform State" section for details.

  required_providers {
    metabase = {
      source  = "flovouin/metabase"
      version = "~> 0.14"
    }
  }
}