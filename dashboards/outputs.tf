# Dashboard URLs
output "main_dashboard_url" {
  description = "URL to access the main analytics dashboard"
  value       = "${var.metabase_url}/dashboard/${metabase_dashboard.analytics.id}"
}

output "tenant_dashboard_urls" {
  description = "URLs to access tenant-specific dashboards"
  value = {
    for k, v in metabase_dashboard.tenant_analytics :
    k => "${var.metabase_url}/dashboard/${v.id}"
  }
}

# Permissions Group IDs
output "global_group_id" {
  description = "Metabase group ID for the Global group (access to all dashboards)"
  value       = metabase_permissions_group.global.id
}

output "tenant_group_ids" {
  description = "Metabase group IDs for each per-tenant group (keyed by tenant key)"
  value = {
    for k, g in metabase_permissions_group.tenant :
    k => g.id
  }
}

