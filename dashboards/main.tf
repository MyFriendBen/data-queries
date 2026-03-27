terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  cloud {
    organization = "MyFriendBen"
    workspaces {
      tags = ["dashboards"]
    }
  }

  required_providers {
    metabase = {
      source  = "flovouin/metabase"
      version = "~> 0.14"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
