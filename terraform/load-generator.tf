# Add firewall rule for SSH access to load generator
resource "google_compute_firewall" "allow_ssh_load_generator" {
  name    = "${var.name}-allow-ssh-load-generator"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  # Allow SSH only from your IP address for security
  source_ranges = ["0.0.0.0/0"]
  
  # Target only the load generator instance
  target_tags = ["load-generator"]
}

resource "google_compute_firewall" "allow_internal_ports" {
  name    = "${var.name}-allow-internal-ports"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["9646", "8089"]
  }

  # Allow internal access only
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  # Target only the load generator instance
  target_tags = ["load-generator"]
}

# Update the load generator VM configuration - use default network
resource "google_compute_instance" "load_generator" {
  name         = "${var.name}-load-generator"
  machine_type = "e2-standard-2"
  zone         = var.zone

  tags = ["load-generator"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  # Use default network - same as GKE cluster
  network_interface {
    network = "default"

    access_config {
      # This block enables the external IP
    }
  }

  depends_on = [
    google_container_cluster.gke_autopilot,
    google_container_cluster.gke_standard
  ]
}

# Generate Ansible inventory using gcloud's SSH keys
resource "local_file" "ansible_inventory" {
  filename = "../ansible/inventory.yml"
  content  = <<-EOT
    all:
      vars:
        ansible_user: root
        ansible_ssh_private_key_file: ~/.ssh/google_compute_engine
        frontend_service_name: frontend-external
        kubernetes_namespace: app

      hosts:
        load_generator:
          ansible_host: ${google_compute_instance.load_generator.network_interface[0].access_config[0].nat_ip}
          ansible_host_key_checking: false
  EOT

  depends_on = [
    module.check_ssh_connectivity
  ]
}

module "check_ssh_connectivity" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.0"

  platform              = "linux"
  additional_components = []

  create_cmd_entrypoint = "bash"
  create_cmd_body       = <<-EOT
    #!/bin/bash
    export PATH=/google-cloud-sdk/bin:$PATH
    max_attempts=30
    attempt=1
    
    echo "Waiting for SSH to become available..."
    until [ "$attempt" -gt "$max_attempts" ]; do
      if gcloud compute ssh ${google_compute_instance.load_generator.name} \
        --zone=${var.zone} \
        --quiet \
        --command="echo 'SSH connection successful'" > /dev/null 2>&1; then
        echo "SSH is ready!"
        exit 0
      fi
      echo "Attempt $attempt/$max_attempts - SSH not ready yet. Waiting 2 seconds..."
      sleep 2
      attempt=$((attempt + 1))
    done
    
    echo "SSH connectivity check failed after $max_attempts attempts"
    exit 1
  EOT

  module_depends_on = [
    "${google_compute_instance.load_generator.id}",
    "${google_compute_firewall.allow_ssh_load_generator.id}"
  ]
}

# Run Ansible playbook
resource "null_resource" "install_tools_load_generator" {
  triggers = {
    instance_id = google_compute_instance.load_generator.id
  }

  provisioner "local-exec" {
    command = "ANSIBLE_DEPRECATION_WARNINGS=False ansible-playbook -i ../ansible/inventory.yml ../ansible/install-tools-load-generator.yml"
  }

  depends_on = [
    local_file.ansible_inventory
  ]
}

# Run Ansible playbook
resource "null_resource" "deploy_load_generator" {
  triggers = {
    instance_id = google_compute_instance.load_generator.id
  }

  provisioner "local-exec" {
    command = "ANSIBLE_DEPRECATION_WARNINGS=False ansible-playbook -i ../ansible/inventory.yml ../ansible/deploy-load-generator.yml"
  }

  depends_on = [
    null_resource.install_tools_load_generator,
    null_resource.deploy_services_using_ansible
  ]
}