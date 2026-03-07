terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  cloud {
    organization = "MyFriendBen"
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
