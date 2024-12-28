resource "time_sleep" "wait_for_cluster" {
  count      = var.logging ? 1 : 0
  depends_on = [local_file.kubeconfig]
  create_duration = "60s"
}

# Create GCP Service Account for Loki
resource "google_service_account" "loki_gcs" {
  count        = var.logging ? 1 : 0
  account_id   = "loki-gcs"
  display_name = "Loki Storage Account"
  depends_on = [
    module.enable_google_apis
  ]
}

# Create Kubernetes Service Account for Loki
resource "kubernetes_service_account" "loki_sa" {
  count = var.logging ? 1 : 0
  metadata {
    name = "loki"
    namespace = "monitoring"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.loki_gcs[0].email
    }
  }
  timeouts {
    create = "5m"
  }
  depends_on = [
    local_file.kubeconfig,
    null_resource.deploy_services_using_ansible,
    time_sleep.wait_for_cluster
  ]
}

# Create IAM policy binding for workload identity
resource "google_service_account_iam_binding" "loki_sa_workload_identity" {
  count              = var.logging ? 1 : 0
  service_account_id = google_service_account.loki_gcs[0].name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/loki]"
  ]
  depends_on = [
    kubernetes_service_account.loki_sa
  ]
}

# Create single GCS bucket for TSDB storage
resource "google_storage_bucket" "loki_storage" {
  count         = var.logging ? 1 : 0
  name          = "loki-storage-tsdb-24"  # Changed name to reflect TSDB usage
  location      = var.region
  force_destroy = true
  
  # Add recommended settings for Loki storage
  uniform_bucket_level_access = true
  versioning {
    enabled = false  # Enables versioning for data safety
  }
  
  lifecycle_rule {
    condition {
      age = 7  # Adjust based on your retention needs
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [
    module.enable_google_apis
  ]
}

resource "google_storage_bucket_iam_member" "loki_storage_object_admin" {
  count  = var.logging ? 1 : 0
  bucket = google_storage_bucket.loki_storage[0].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.loki_gcs[0].email}"
}