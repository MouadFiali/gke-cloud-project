# # Add this module to check SSH connectivity
# module "check_ssh_connectivity" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = []

#   create_cmd_entrypoint = "bash"
#   create_cmd_body       = <<-EOT
#     #!/bin/bash
#     export PATH=/google-cloud-sdk/bin:$PATH
#     max_attempts=30
#     attempt=1
    
#     echo "Waiting for SSH to become available..."
#     until [ "$attempt" -gt "$max_attempts" ]; do
#       if gcloud compute ssh ${google_compute_instance.load_generator.name} \
#         --zone=${var.zone} \
#         --quiet \
#         --command="echo 'SSH connection successful'" > /dev/null 2>&1; then
#         echo "SSH is ready!"
#         exit 0
#       fi
#       echo "Attempt $attempt/$max_attempts - SSH not ready yet. Waiting 2 seconds..."
#       sleep 2
#       attempt=$((attempt + 1))
#     done
    
#     echo "SSH connectivity check failed after $max_attempts attempts"
#     exit 1
#   EOT

#   module_depends_on = [
#     "${google_compute_instance.load_generator.id}",
#     "${google_compute_firewall.allow_ssh_load_generator.id}"
#   ]
# }

# # Module for copying and executing install_docker.sh
# module "copy_execute_docker" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = []

#   # First, copy the docker installation script
#   create_cmd_entrypoint = "gcloud"
#   create_cmd_body       = "compute scp ../scripts/install_docker.sh ${google_compute_instance.load_generator.name}:/tmp/install_docker.sh --zone=${var.zone}"

#   module_depends_on = [
#     module.check_ssh_connectivity
#   ]
# }

# # Module for executing install_docker.sh
# module "execute_docker_script" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = []

#   # Then execute the docker installation script
#   create_cmd_entrypoint = "gcloud"
#   create_cmd_body       = "compute ssh ${google_compute_instance.load_generator.name} --zone=${var.zone} --command='chmod +x /tmp/install_docker.sh && sudo /tmp/install_docker.sh'"

#   module_depends_on = [
#     module.copy_execute_docker
#   ]
# }

# # Module for copying and executing install_ansible.sh
# module "copy_execute_docker_compose" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = []

#   # First, copy the docker compose file
#   create_cmd_entrypoint = "gcloud"
#   create_cmd_body       = "compute scp ../scripts/docker-compose.yml ${google_compute_instance.load_generator.name}:/tmp/docker-compose.yml --zone=${var.zone}"

#   module_depends_on = [
#     module.execute_docker_script
#   ]
# }

# # Modified run_load_generator_container module
# module "run_load_generator_container" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = []

#   create_cmd_entrypoint = "bash"
#   create_cmd_body       = <<-EOT
#     #!/bin/bash
    
#     # Get the frontend IP using kubectl directly
#     FRONTEND_IP=$(kubectl get service frontend-external -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
#     if [ -z "$FRONTEND_IP" ]; then
#       echo "Failed to get frontend IP address" >&2
#       exit 1
#     fi
    
#     echo "Frontend IP is: $FRONTEND_IP"
    
#     # Run docker-compose with sudo and the retrieved IP
#     gcloud compute ssh ${google_compute_instance.load_generator.name} \
#       --zone=${var.zone} \
#       --quiet \
#       --command="sudo -E sh -c 'FRONTEND_ADDR_IP=$FRONTEND_IP:80 && export FRONTEND_ADDR_IP && cd /tmp && docker compose up -d'"
#   EOT

#   module_depends_on = [
#     "${module.copy_execute_docker_compose.wait}",
#     "${null_resource.wait_conditions.id}"
#   ]
# }

# module "get_frontend_ip" {
#   source  = "terraform-google-modules/gcloud/google"
#   version = "~> 3.0"

#   platform              = "linux"
#   additional_components = ["kubectl"]

#   create_cmd_entrypoint = "kubectl"
#   create_cmd_body       = "get service frontend-external -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"

#   module_depends_on = [
#     resource.null_resource.wait_conditions
#   ]
# }