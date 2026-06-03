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
      source = "flovouin/metabase"
      # >= 0.14.2: fixes a JSON unmarshal error in metabase_permissions_graph
      # when the Metabase API returns create_queries as an object (granular
      # per-schema perms) rather than a scalar string. Without it, terraform
      # plan/apply fails during state refresh once any group's create-queries
      # goes granular. See provider 0.14.2 changelog.
      version = ">= 0.14.2, ~> 0.14"
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
