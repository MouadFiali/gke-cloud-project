# local variable to check if load generator should be created
locals {
  create_load_generator = (var.deploy_load_generator_server && 
    (var.deploy_canary_frontend || var.create_frontend_external_ip || var.use_istio_virtual_service))
}

# Add firewall rule for SSH access to load generator
resource "google_compute_firewall" "allow_ssh_load_generator" {
  count   = local.create_load_generator ? 1 : 0
  name    = "${var.name}-allow-ssh-load-generator"
  network = "main"

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["load-generator"]
  depends_on = [ google_compute_network.main ]
}

resource "google_compute_firewall" "allow_internal_ports" {
  count   = local.create_load_generator ? 1 : 0
  name    = "${var.name}-allow-internal-ports"
  network = "main"

  allow {
    protocol = "tcp"
    ports    = ["9646", "8089"]
  }
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  target_tags   = ["load-generator"]
  depends_on = [ google_compute_network.main ]
}

# Update the load generator VM configuration - use default network
resource "google_compute_instance" "load_generator" {
  count        = local.create_load_generator ? 1 : 0
  name         = "${var.name}-load-generator"
  machine_type = "e2-standard-2"
  zone         = var.zone

  tags = ["load-generator"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.self_link

    access_config {
      # Enables an external IP
    }
  }

  depends_on = [
    google_container_cluster.gke_autopilot,
    google_container_cluster.gke_standard
  ]
}

# Generate Ansible inventory using gcloud's SSH keys
resource "local_file" "ansible_inventory" {
  count    = local.create_load_generator ? 1 : 0

  
  filename = "../ansible/inventory.yml"
  content  = <<-EOT
    all:
      vars:
        ansible_user: root
        ansible_ssh_private_key_file: ../terraform/id_rsa

      hosts:
        load_generator:
          ansible_host: ${google_compute_instance.load_generator[count.index].network_interface[0].access_config[0].nat_ip}
          ansible_host_key_checking: false
  EOT

  depends_on = [
    null_resource.check_connectivity
  ]
}

resource "null_resource" "check_connectivity" {
  count = local.create_load_generator ? 1 : 0


  triggers = {
    instance_id = google_compute_instance.load_generator[count.index].id
    firewall_id = google_compute_firewall.allow_ssh_load_generator[count.index].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      max_attempts=30
      attempt=1
      
      # SSH options for secure, non-interactive connection
      SSH_OPTS="-i ../terraform/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"
      
      echo "Waiting for SSH connectivity..."
      
      until [ "$attempt" -gt "$max_attempts" ]; do
        if ssh $${SSH_OPTS} ${var.gcpUser}@${google_compute_instance.load_generator[count.index].network_interface[0].access_config[0].nat_ip} \
          "echo 'SSH connection successful'" > /dev/null 2>&1; then
          echo "SSH is ready!"
          exit 0
        fi
        
        echo "Attempt $attempt/$max_attempts - Waiting for SSH... Retrying in 2 seconds..."
        sleep 2
        attempt=$((attempt + 1))
      done
      
      echo "SSH connectivity check failed after $max_attempts attempts"
      exit 1
    EOT
  }

  depends_on = [
    google_compute_instance.load_generator,
    google_compute_firewall.allow_ssh_load_generator
  ]
}

# Run Ansible playbook
resource "null_resource" "install_tools_load_generator" {
  count = local.create_load_generator ? 1 : 0

  triggers = {
    instance_id = google_compute_instance.load_generator[count.index].id
  }

  provisioner "local-exec" {
    command = "ANSIBLE_DEPRECATION_WARNINGS=False ansible-playbook -i ../ansible/inventory.yml ../ansible/install-tools-load-generator.yml"
  }

  depends_on = [
    local_file.ansible_inventory
  ]
}

# Deploy load generator
resource "null_resource" "deploy_load_generator" {
  count = local.create_load_generator ? 1 : 0

  triggers = {
    instance_id = google_compute_instance.load_generator[0].id
  }

  provisioner "local-exec" {
    command = "ANSIBLE_DEPRECATION_WARNINGS=False ansible-playbook -i ../ansible/inventory.yml ../ansible/deploy-load-generator.yml --extra-vars \"app_namespace=${var.namespace} deploy_canary_frontend=${var.deploy_canary_frontend} use_istio_virtual_service=${var.use_istio_virtual_service}\""
  }

  depends_on = [
    null_resource.install_tools_load_generator,
    null_resource.deploy_services_using_ansible
  ]
}