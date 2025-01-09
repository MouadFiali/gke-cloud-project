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


variable "gcpUser" {
  type = string
  description = "The GCP user to apply this config to"
  default = "root"
}

variable "service_account_path" {
  type        = string
  description = "path to the service account key file"
  
}

variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to apply this config to"
}

variable "name" {
  type        = string
  description = "Name given to the new GKE cluster"
  default     = "online-boutique"
}

variable "region" {
  type        = string
  description = "Region of the new GKE cluster"
  default     = "europe-west6"
}

variable "zone" {
  type        = string
  description = "Zone of the new GKE cluster"
  default     = "europe-west6-b"
}

variable "namespace" {
  type        = string
  description = "Kubernetes Namespace in which the Online Boutique resources are to be deployed"
  default     = "default"
}

variable "tracing" {
  type        = bool
  description = "Enable tracing using open telemetry tempo and grafana"
  default     = false
} 

variable "logging" {
  type        = bool
  description = "Enable logging using open telemetry, loki and grafana"
  default     = false
}

variable "enable_autopilot" {
  description = "Enable Autopilot mode for the GKE cluster"
  type        = bool
  default     = true
}

variable "memorystore" {
  type        = bool
  description = "If true, Online Boutique's in-cluster Redis cache will be replaced with a Google Cloud Memorystore Redis cache"
}

variable "grafana_smtp_host" {
  type        = string
  description = "SMTP host for Grafana"
}

variable "grafana_smtp_user" {
  type        = string
  description = "SMTP user for Grafana"
}

variable "grafana_smtp_password" {
  type        = string
  description = "SMTP password for Grafana"
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaling"
  type        = bool
  default     = true
}

variable "enable_horizontal_pod_autoscaling" {
  description = "Enable horizontal pod autoscaling"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of nodes in the node pool"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes in the node pool"
  type        = number
  default     = 30
}

variable "istio_sidecar" {
  description = "Enable Istio sidecar injection"
  type        = bool
  default     = true
}

variable "use_istio_virtual_service" {
  description = "Use Istio VirtualService for routing"
  type        = bool
  default     = false
}

variable "create_frontend_external_ip" {
  description = "Create an external IP for the frontend service"
  type        = bool
  default     = false
}

variable "deploy_canary_frontend" {
  description = "Deploy a canary frontend service using flagger"
  type        = bool
  default     = true
}

variable "deploy_load_generator_server" {
  description = "Deploy a load generator server"
  type        = bool
  default     = true
}