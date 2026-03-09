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
