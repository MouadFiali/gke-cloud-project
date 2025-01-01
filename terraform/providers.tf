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

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.9.0"
    }
    time = {
      source = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

provider "kubernetes" {
  host  = "https://${var.enable_autopilot ? google_container_cluster.gke_autopilot[0].endpoint : google_container_cluster.gke_standard[0].endpoint}"
  token = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(
    var.enable_autopilot ? google_container_cluster.gke_autopilot[0].master_auth[0].cluster_ca_certificate : google_container_cluster.gke_standard[0].master_auth[0].cluster_ca_certificate
  )
}

provider "google" {
  credentials = file(var.service_account_path)
  project = var.gcp_project_id
  region  = var.region
}
