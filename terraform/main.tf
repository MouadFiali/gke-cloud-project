# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Definition of local variables
locals {
  # API configurations
  base_apis = [
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com"
  ]
  memorystore_apis = ["redis.googleapis.com"]
  cluster_name     = var.enable_autopilot ? google_container_cluster.gke_autopilot[0].name : google_container_cluster.gke_standard[0].name
}

# Generate a new SSH key
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Write the private key to a local file
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa"
  file_permission = "0600"
}

# Enable Google Cloud APIs
module "enable_google_apis" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 17.0"

  project_id                  = var.gcp_project_id
  disable_services_on_destroy = false

  activate_apis = concat(local.base_apis, var.memorystore ? local.memorystore_apis : [])
}

# Create GKE Autopilot cluster
resource "google_container_cluster" "gke_autopilot" {
  count = var.enable_autopilot ? 1 : 0

  name     = var.name
  location = var.region

  # Enable autopilot for this cluster
  enable_autopilot = true

  # Set an empty ip_allocation_policy to allow autopilot cluster to spin up correctly
  ip_allocation_policy {
  }

  # Avoid setting deletion_protection to false
  # until you're ready (and certain you want) to destroy the cluster.
  deletion_protection = false

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  depends_on = [
    module.enable_google_apis
  ]
}

# Create GKE Standard cluster
resource "google_container_cluster" "gke_standard" {
  count = var.enable_autopilot ? 0 : 1

  name     = var.name
  location = var.zone

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Set networking config
  ip_allocation_policy {
  }

  deletion_protection = false

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  depends_on = [
    module.enable_google_apis
  ]
}

# Create node pool for Standard cluster
resource "google_container_node_pool" "primary_nodes" {
  count = var.enable_autopilot ? 0 : 1

  name       = "${var.name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.gke_standard[0].name
  node_count = 4

  node_config {
    machine_type = "e2-standard-2"

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Get the current client configuration
data "google_client_config" "current" {}

# Update the kubeconfig generation
resource "local_file" "kubeconfig" {
  depends_on = [
    google_container_cluster.gke_autopilot,
    google_container_cluster.gke_standard
  ]

  filename = pathexpand("~/.kube/config")
  content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name    = local.cluster_name
    endpoint        = var.enable_autopilot ? google_container_cluster.gke_autopilot[0].endpoint : google_container_cluster.gke_standard[0].endpoint
    cluster_ca      = var.enable_autopilot ? google_container_cluster.gke_autopilot[0].master_auth[0].cluster_ca_certificate : google_container_cluster.gke_standard[0].master_auth[0].cluster_ca_certificate
    client_token    = data.google_client_config.current.access_token
    gcp_project_id  = var.gcp_project_id
    location        = var.enable_autopilot ? var.region : var.zone
  })

  file_permission = "0600"
}

resource "null_resource" "deploy_services_using_ansible" {
  depends_on = [module.gcloud]

  provisioner "local-exec" {
    command = "cd ../scripts && ./run_ansible_playbooks.sh ${var.namespace} ${var.tracing} ${var.logging}"
  }
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    ssh-keys = "${var.gcpUser}:${tls_private_key.ssh.public_key_openssh}"
  }
}
