# ================================================================================
# Pub/Sub: Async cartoonify job queue
# ================================================================================
# Replaces SQS from aws-cartoonify. The submit function publishes here;
# the worker Cloud Function is triggered by Eventarc on this topic.
# ================================================================================

# Primary topic — submit function publishes job requests here
resource "google_pubsub_topic" "jobs" {
  name = "cartoonify-jobs"
}

# Dead-letter topic — receives messages that exhaust all retries
resource "google_pubsub_topic" "jobs_dlq" {
  name = "cartoonify-jobs-dlq"
}

# Subscription consumed by the Eventarc-triggered worker function.
# ack_deadline_seconds = 300 — exceeds the 300s worker timeout, prevents
# Pub/Sub from redelivering a message while the worker is still processing.
resource "google_pubsub_subscription" "jobs_sub" {
  name  = "cartoonify-jobs-sub"
  topic = google_pubsub_topic.jobs.name

  ack_deadline_seconds = 300

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.jobs_dlq.id
    max_delivery_attempts = 5
  }
}

# Allow Pub/Sub service account to publish to DLQ for dead-lettering
data "google_project" "project" {
  project_id = local.credentials.project_id
}

resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.jobs_dlq.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  subscription = google_pubsub_subscription.jobs_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
