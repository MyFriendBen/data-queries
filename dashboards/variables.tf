variable "database_host" {
  description = "Database host"
  type        = string
  default     = "localhost"
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "mfb"
}

variable "database_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "global_db_credentials" {
  description = "Database credentials for global dashboard (admin access)"
  type = object({
    username = string
    password = string
  })
  sensitive = true
}

variable "tenants" {
  description = "Map of tenant configurations (non-sensitive)"
  type = map(object({
    name         = string
    display_name = string
  }))
  default = {
    nc = {
      name         = "nc"
      display_name = "North Carolina"
    }
    co = {
      name         = "co"
      display_name = "Colorado"
    }
    tx = {
      name         = "tx"
      display_name = "Texas"
    }
    il = {
      name         = "il"
      display_name = "Illinois"
    }
    ma = {
      name         = "ma"
      display_name = "Massachusetts"
    }
    cesn = {
      name         = "cesn"
      display_name = "CESN"
    }
    co_tax_calculator = {
      name         = "co_tax_calculator"
      display_name = "CO Tax Calculator"
    }
  }
}

variable "tenant_db_credentials" {
  description = "Database credentials for each tenant (sensitive)"
  type = map(object({
    username = string
    password = string
  }))
  sensitive = true
}

# Metabase configuration variables
variable "metabase_url" {
  description = "The URL of the Metabase instance"
  type        = string
  default     = "http://localhost:3001"
}

variable "metabase_admin_email" {
  description = "Metabase admin email for API access"
  type        = string
  default     = "admin@yourcompany.com"
}

variable "metabase_admin_password" {
  description = "Metabase admin password for API access"
  type        = string
  sensitive   = true
}

# BigQuery configuration variables
variable "gcp_project_id" {
  description = "Google Cloud Project ID for BigQuery"
  type        = string
  default     = "your-gcp-project-id"
}

variable "bigquery_service_account_key_path" {
  description = "Path to BigQuery service account JSON key file (for local development)"
  type        = string
  default     = "./secrets/bigquerykey.json"
}

variable "bigquery_service_account_key_content" {
  description = "BigQuery service account JSON key content (for production - pass from secret manager)"
  type        = string
  sensitive   = true
  default     = null
}

variable "bigquery_analytics_dataset" {
  description = "BigQuery dataset name where dbt analytics marts are materialized ( matched dbt profile dataset)"
  type        = string
  default     = "analytics"
}

variable "database_sync_wait_seconds" {
  description = "Seconds to wait for Metabase to sync database schemas before creating cards/dashboards"
  type        = number
  default     = 60
}

variable "database_ssl" {
  description = "Enable SSL for PostgreSQL connections (required for most production databases)"
  type        = bool
  default     = false
}

variable "bigquery_enabled" {
  description = "Enable BigQuery data source in Metabase. Requires bigquery_service_account_key_content or a valid key file."
  type        = bool
  default     = false
}

locals {
  # Use content if provided, otherwise read from file path (if it exists)
  bigquery_key_from_file = fileexists(var.bigquery_service_account_key_path) ? file(var.bigquery_service_account_key_path) : null
  bigquery_key           = var.bigquery_enabled ? coalesce(var.bigquery_service_account_key_content, local.bigquery_key_from_file) : ""

  # Build tenant credentials with fallback to global credentials for tenants not explicitly configured
  tenant_credentials = {
    for key, tenant in var.tenants : key => lookup(var.tenant_db_credentials, key, {
      username = var.global_db_credentials.username
      password = var.global_db_credentials.password
    })
  }

  # Ordered list of tenant keys for sequential collection creation.
  #
  # WHY THIS EXISTS: Metabase has a race condition when collections are created
  # concurrently — parallel writes to collection_permission_graph_revision cause
  # a duplicate key error. We work around it by creating each collection as a
  # separate named resource with a chained depends_on (see metabase.tf). This
  # list drives the auto-generated tenant_collection_map so the map never needs
  # manual editing.
  #
  # IMPORTANT: Always append new tenants to the END of this list.
  # Do not reorder existing entries — that would break the depends_on chain and
  # cause Terraform to see resource name mismatches.
  #
  # When adding a new tenant:
  #   1. Add the tenant key here (end of list)
  #   2. Add a new metabase_collection resource block in metabase.tf, chaining
  #      depends_on to the last existing collection resource
  #   (tenant_collection_map updates automatically — no third edit needed)
  tenant_collection_order = [
    "nc",
    "co",
    "tx",
    "il",
    "ma",
    "cesn",
    "co_tax_calculator",
  ]
}
