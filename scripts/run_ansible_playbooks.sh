#!/bin/bash

NAMESPACE="${1:-default}"
TRACING="${2:-false}"
LOGGING="${3:-false}"

# Navigate to the ansible directory
cd ../ansible



# Run install-istio-flagger playbook
ansible-playbook install-istio-flagger.yml

# Check if the third playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run install-istio-flagger.yaml"
    exit 1
fi

# Run the deploy-argocd playbook
ansible-playbook deploy-argocd.yaml --extra-vars "app_namespace=$APP_NAMESPACE tracing=$TRACING logging=$LOGGING"

# Check if the first playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run deploy-argocd.yaml"
    exit 1
fi

# Run the prometheus-grafana playbook
ansible-playbook prometheus-grafana.yml --extra-vars "tracing=$TRACING logging=$LOGGING"

# Check if the second playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run prometheus-grafana.yml"
    exit 1
fi

echo "All playbooks ran successfully"