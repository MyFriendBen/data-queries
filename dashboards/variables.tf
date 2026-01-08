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
  default = {
    username = "mfb"
    password = "admin_password"
  }
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
  default = {
    nc = {
      username = "nc"
      password = "myfriendben"
    }
    co = {
      username = "co"
      password = "colorado_password"
    }
  }
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
  default     = "your_admin_password"
}

# BigQuery configuration variables
variable "gcp_project_id" {
  description = "Google Cloud Project ID for BigQuery"
  type        = string
  default     = "your-gcp-project-id"
}

variable "bigquery_service_account_path" {
  description = "Path to BigQuery service account JSON key file"
  type        = string
  default     = "../dbt/secrets/bigquerykey.json"
}