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

locals {
  # Use content if provided, otherwise read from file path (if it exists)
  bigquery_key_from_file = fileexists(var.bigquery_service_account_key_path) ? file(var.bigquery_service_account_key_path) : null
  bigquery_key           = coalesce(var.bigquery_service_account_key_content, local.bigquery_key_from_file)
}