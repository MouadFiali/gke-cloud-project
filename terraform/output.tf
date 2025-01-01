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

output "cluster_location" {
  description = "Location of the cluster"
  value       = var.enable_autopilot ? resource.google_container_cluster.gke_autopilot[0].location : resource.google_container_cluster.gke_standard[0].location
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.enable_autopilot ? resource.google_container_cluster.gke_autopilot[0].name : resource.google_container_cluster.gke_standard[0].name
}


# Output the external IP
output "ingress_ip" {
  description = "External IP address of the ASM ingress gateway"
  value       = data.kubernetes_service.ingress_gateway.status.0.load_balancer.0.ingress.0.ip
}