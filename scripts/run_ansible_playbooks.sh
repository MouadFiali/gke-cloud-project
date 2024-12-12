#!/bin/bash

# Navigate to the ansible directory
cd ../ansible

# Run the deploy-argocd playbook
ansible-playbook deploy-argocd.yaml

# Check if the first playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run deploy-argocd.yaml"
    exit 1
fi

# Run the prometheus-grafana playbook
ansible-playbook prometheus-grafana.yml

# Check if the second playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run prometheus-grafana.yml"
    exit 1
fi

echo "All playbooks ran successfully"