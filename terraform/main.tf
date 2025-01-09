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
    "cloudresourcemanager.googleapis.com",
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

resource "google_compute_network" "main" {
  name                            = "main"
  routing_mode                    = "REGIONAL"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = false

}

resource "google_compute_subnetwork" "private" {
  name                     = "pelstix-private-subnet"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "k8s-pod-range"
    ip_cidr_range = "10.1.0.0/16"
  }
  secondary_ip_range {
    range_name    = "k8s-service-range"
    ip_cidr_range = "10.2.0.0/16"
  }
}

resource "google_compute_router" "router" {
  name    = "router-new"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "nat" {
  name   = "nat"
  router = google_compute_router.router.name
  region = var.region

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  nat_ip_allocate_option             = "MANUAL_ONLY"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  nat_ips = [google_compute_address.nat.self_link]
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address
resource "google_compute_address" "nat" {
  name         = "nat"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

# Create GKE Standard cluster
resource "google_container_cluster" "gke_standard" {
  count = var.enable_autopilot ? 0 : 1

  name     = var.name
  location = var.region

  network                  = google_compute_network.main.self_link
  subnetwork               = google_compute_subnetwork.private.self_link

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8s-service-range"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block = "10.3.0.0/28"
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
  cluster    = google_container_cluster.gke_standard[0].name
  initial_node_count = var.min_node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-2"

    labels = {
      role = "general"
    }
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  dynamic "autoscaling" {
    for_each = var.enable_cluster_autoscaler ? [1] : []
    content {
      min_node_count = var.min_node_count
      max_node_count = var.max_node_count
    }
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

resource "null_resource" "reload_kubectl_config" {
  depends_on = [local_file.kubeconfig]

  provisioner "local-exec" {
    command = "kubectl config view --raw > /dev/null"
  }
}

# In main.tf
resource "null_resource" "deploy_services_using_ansible" {
  depends_on = [
    null_resource.reload_kubectl_config
  ]

  provisioner "local-exec" {
    command = <<-EOT
      cd ../scripts && ./run_ansible_playbooks.sh \
      ${var.namespace} \
      ${var.tracing} \
      ${var.logging} \
      ${var.grafana_smtp_host} \
      ${var.grafana_smtp_user} \
      ${var.grafana_smtp_password} \
      ${var.istio_sidecar} \
      ${var.use_istio_virtual_service} \
      ${var.deploy_canary_frontend} \
      ${var.create_frontend_external_ip} \
      ${var.enable_horizontal_pod_autoscaling} \
    EOT
  }
}

data "kubernetes_service" "ingress_gateway" {
  count = var.use_istio_virtual_service || var.deploy_canary_frontend ? 1 : 0
  
  depends_on = [null_resource.deploy_services_using_ansible]
  
  metadata {
    name      = "asm-ingressgateway"
    namespace = "asm-ingress"
  }
}


resource "google_compute_project_metadata" "default" {
  metadata = {
    ssh-keys = "${var.gcpUser}:${tls_private_key.ssh.public_key_openssh}"
  }
}
