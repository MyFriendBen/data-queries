terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    metabase = {
      source  = "flovouin/metabase"
      version = "~> 0.13"
    }
  }
}