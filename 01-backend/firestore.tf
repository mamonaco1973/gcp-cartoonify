# ================================================================================
# Firestore: Composite Indexes
# ================================================================================
# Firestore requires composite indexes for queries that filter + order on
# different fields. These are needed for:
#   - history: owner == uid, ORDER BY created_at DESC, LIMIT 50
#   - quota:   owner == uid AND created_at >= today_start
# ================================================================================

# Index for /history (newest-first per user)
resource "google_firestore_index" "jobs_owner_created_desc" {
  project    = local.credentials.project_id
  collection = "cartoonify_jobs"

  fields {
    field_path = "owner"
    order      = "ASCENDING"
  }

  fields {
    field_path = "created_at"
    order      = "DESCENDING"
  }
}

# Index for daily quota check (range query per user on today's jobs)
resource "google_firestore_index" "jobs_owner_created_asc" {
  project    = local.credentials.project_id
  collection = "cartoonify_jobs"

  fields {
    field_path = "owner"
    order      = "ASCENDING"
  }

  fields {
    field_path = "created_at"
    order      = "ASCENDING"
  }
}
