# GKE Cloud Project

This repository contains the implementation of a cloud-native microservices deployment with enhanced monitoring, scaling, and deployment capabilities. This project is heavily based on the [Cloud-Native Microservices Demo Application Of Google](https://github.com/GoogleCloudPlatform/microservices-demo)

This README provides an overview of the repository structure, deployment instructions, and the enhancements we made to the original project. A detailed explanation of our work can be found in the [Project Report](./report.md).

## Repository Structure

### Base Steps
- [`/terraform/`](./terraform/) - Infrastructure provisioning files
  - GKE cluster setup
  - Load generator VM provisioning
- [`/kustomize/`](./kustomize/) - Kustomize base and overlay files
  - Base configuration for the application
  - Overlay configurations for different components
- [`/scripts/`](./scripts/) - Helper files for deployment
    - [`docker-compose.yml`](./scripts/docker-compose.yml) - Docker Compose file for locust load generator (used in to install locust in the load generator VM)

### Intermediate Steps (Our enhancements)
- [`/helm-chart/`](./helm-chart/) - Enhanced Helm Chart with:
    - Custom service versioning
    - Canary deployment configuration
    - Horizontal Pod Autoscaler configuration
    - Updated monitoring components (Tracing, Logging etc.)
- [`.gitlab-ci.yml`](.gitlab-ci.yml), [`.gitlab-ci-deploy.yml`](.gitlab-ci-deploy.yml), [`.gitlab-ci-helm.yml`](.gitlab-ci-helm.yml) - GitLab CI/CD pipeline configuration

### Advanced & Bonus Steps
In all the steps, our goal was to automate everything we do as much as possible. That's why most of the work is done using Ansible playbooks:

- [`/ansible/`](./ansible/) - Automation and monitoring setup
  - This folder contains Ansible playbooks for:
    - [`prometheus-grafana`](./ansible/prometheus-grafana.yml) Setting up monitoring tools
    - [`deploy-argocd`](./ansible/deploy-argocd.yaml) Installing and configuring Argocd
    - [`install-istio-flagger`](./ansible/install-istio-flagger.yml) Installing and configuring Istio, Flagger and Kiali
    - [`deploy-load-generator`](./ansible/deploy-load-generator.yml) | [`install-tools-load-generator`](./ansible/install-tools-load-generator.yml) Installing and configuring Locust
    - [`swarm-load-generator`](./ansible/swarm-load-generator.yml) Automating application swarming for load testing
  - [`custom-values/`](./ansible/custom-values/) - Configuration for ArgoCD & observability tools
  - [`dashboards/`](./ansible/dashboards/) - Custom Grafana dashboards
- [`run_ansible_playbooks.sh`](./scripts/run_ansible_playbooks.sh) - Ansible playbooks execution script

## Deployment Instructions

### Prerequisites
- Google Cloud Platform account
- kubectl configured
- Helm v3.x
- Ansible
- Terraform
- jq (for JSON parsing)

### Step-by-Step Deployment

1. **GCP Project Setup**
    - Create a new GCP project
    - Create a service account with the necessary roles & permissions
    - Download the service account key and place it in the root directory as `project-sa.json`

2. **Infrastructure Provisioning**
    - Navigate to the [`terraform`](./terraform/) and change the values in [`terraform.tfvars`](./terraform/terraform.tfvars) as needed
    - Run the following commands to provision the infrastructure:
        ```bash
        terraform init
        terraform apply
        ```
    - By default, this command will create the GKE cluster and a VM for the load generator and also deploy the application with the default configuration.

### Default Configuration

The default configuration provided in `terraform.tfvars` includes:

- The default node count is 1, meaning that 1 node will be deployed in each zone of the selected region (`europe-west`6 by default)
- Application deployed in `app` namespace 
- Observability enabled:
    - Tracing with Tempo
    - Logging with Loki
    - Metrics with Prometheus/Grafana
- Advanced features enabled:
    - Cluster autoscaling
    - Horizontal Pod Autoscaling
    - Service mesh (Istio sidecars)
    - Canary deployment support for `frontend service`
- Load testing environment:
    - Dedicated VM for load generator
    - Load generator server deployed

To customize the deployment configuration, you can modify the [`terraform.tfvars`](./terraform/terraform.tfvars) file.

