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

# Collection IDs
output "tenant_collection_ids" {
  description = "IDs of tenant collections (useful for organizing new cards)"
  value = {
    for k, v in local.tenant_collection_map :
    k => v.id
  }
}

# Database IDs
output "bigquery_database_id" {
  description = "ID of the BigQuery database in Metabase"
  value       = metabase_database.bigquery.id
}

output "postgres_database_id" {
  description = "ID of the global PostgreSQL database in Metabase"
  value       = metabase_database.postgres.id
}

output "tenant_postgres_database_ids" {
  description = "IDs of tenant-specific PostgreSQL databases in Metabase"
  value = {
    for k, v in metabase_database.tenant_postgres :
    k => v.id
  }
}

# Card IDs
output "conversion_funnel_card_id" {
  description = "ID of the conversion funnel card"
  value       = metabase_card.conversion_funnel.id
}

output "screen_count_card_id" {
  description = "ID of the screen count card"
  value       = metabase_card.screen_count.id
}

output "tenant_screen_count_card_ids" {
  description = "IDs of tenant-specific screen count cards"
  value = {
    for k, v in metabase_card.tenant_screen_count :
    k => v.id
  }
}

# Quick Access Summary
output "quick_access" {
  description = "Quick access URLs and important IDs"
  value = {
    metabase_url      = var.metabase_url
    main_dashboard    = "${var.metabase_url}/dashboard/${metabase_dashboard.analytics.id}"
    tenant_dashboards = {
      for k, v in metabase_dashboard.tenant_analytics :
      k => "${var.metabase_url}/dashboard/${v.id}"
    }
  }
}
