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
    name           = string
    display_name   = string
    white_label_id = number
  }))

  validation {
    condition     = alltrue([for t in var.tenants : t.white_label_id > 0 && floor(t.white_label_id) == t.white_label_id])
    error_message = "Each tenant white_label_id must be a positive integer."
  }

  validation {
    condition     = length(distinct([for t in var.tenants : t.white_label_id])) == length(var.tenants)
    error_message = "Each tenant must have a unique white_label_id."
  }

  default = {
    nc = {
      name           = "nc"
      display_name   = "North Carolina"
      white_label_id = 5
    }
    co = {
      name           = "co"
      display_name   = "Colorado"
      white_label_id = 1
    }
    tx = {
      name           = "tx"
      display_name   = "Texas"
      white_label_id = 40
    }
    wa = {
      name           = "wa"
      display_name   = "Washington"
      white_label_id = 41
    }
    il = {
      name           = "il"
      display_name   = "Illinois"
      white_label_id = 39
    }
    ma = {
      name           = "ma"
      display_name   = "Massachusetts"
      white_label_id = 38
    }
    cesn = {
      name           = "cesn"
      display_name   = "CESN"
      white_label_id = 4
    }
    co_tax_calculator = {
      name           = "co_tax_calculator"
      display_name   = "CO Tax Calculator"
      white_label_id = 3
    }
    ks = {
      name           = "ks"
      display_name   = "Kansas"
      white_label_id = 42
    }
    mo = {
      name           = "mo"
      display_name   = "Missouri"
      white_label_id = 43
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

  # Tenants whose connection would be built from the global credentials rather than
  # their own read-only role. The global credential is the dbt build user, which owns
  # the analytics tables; the RLS policy is TO PUBLIC and the tables are not FORCE ROW
  # LEVEL SECURITY, so the owner bypasses RLS and the app.white_label_id GUC is ignored.
  # Such a connection serves EVERY tenant's rows to that tenant's Viewers/Editors.
  tenants_using_global_credentials = [
    for key, creds in local.tenant_credentials : key
    if creds.username == var.global_db_credentials.username
  ]
}

# Surfaces the RLS-bypass fallback early, at the top of plan output, before Terraform
# reaches the resources. A check block only WARNS and does not affect the exit code —
# the blocking guard is the precondition on metabase_database.tenant_postgres
# (metabase.tf), which refuses to create a connection whose username is not that
# tenant's wl_<state>_<white_label_id>_ro role. This is intentionally the looser of the
# two: it catches the specific global-credential fallback for every tenant at once,
# including tenants whose resources a targeted plan would skip.
check "tenant_credentials_are_tenant_scoped" {
  assert {
    condition = length(local.tenants_using_global_credentials) == 0
    # nonsensitive() so the tenant keys actually print: the credential maps are
    # sensitive, which would otherwise redact the whole message. Only the keys are
    # exposed, never a username or password.
    error_message = join(" ", [
      "These tenants would connect as the global (RLS-exempt owner) credential and expose every tenant's rows:",
      join(", ", nonsensitive(local.tenants_using_global_credentials)),
      "- create the wl_<state>_<white_label_id>_ro role and set <STATE>_DB_USER/<STATE>_DB_PASS",
      "in the production environment, then re-run. See README 'Wire Up CI Credentials'.",
    ])
  }
}

# Launch date for the 211 Metro Chicago referrer dashboard (chicago211_dashboard.tf).
#
# Null until they launch, which is the current state: with no date set, no date
# predicate is emitted. That is safe because the referrer predicate already
# excludes every pre-launch screener — nothing can carry ?referrer=211chicago
# before the link exists. Set this at launch so a stray pre-launch test link
# cannot show up in their numbers either.
#
# Deploy-time value, deliberately not a dashboard filter: a viewer must not be
# able to move it. Changing it is one edit plus an apply, and every card picks
# it up at once.
variable "chicago211_launch_date" {
  description = "ISO date (YYYY-MM-DD); 211 Metro Chicago cards count only screeners submitted on or after it. Null disables the date predicate."
  type        = string
  default     = null

  # Interpolated straight into card SQL, so constrain the shape.
  validation {
    condition     = var.chicago211_launch_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.chicago211_launch_date))
    error_message = "chicago211_launch_date must be null or an ISO date, e.g. 2026-11-01."
  }
}
