#!/bin/bash

NAMESPACE="${1:-default}"
TRACING="${2:-false}"
LOGGING="${3:-false}"
GRAFANA_SMTP_HOST="${4:-}"
GRAFANA_SMTP_USER="${5:-}"
GRAFANA_SMTP_PASSWORD="${6:-}"
SIDECARS="${7:-}"
VIRTUAL_SERVICE="${8:-}"
CANARY="${9:-}"
EXTERNAL_FRONTEND_SERVICE="${10:-}"
HPA="${11:-}"

# Navigate to the ansible directory
cd ../ansible

# Run install-istio-flagger playbook
ansible-playbook install-istio-flagger.yml --extra-vars "app_namespace=$NAMESPACE sidecars=$SIDECARS virtual_service=$VIRTUAL_SERVICE canary=$CANARY"

# Check if the third playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run install-istio-flagger.yaml"
    exit 1
fi

# Run the deploy-argocd playbook
ansible-playbook deploy-argocd.yaml --extra-vars "app_namespace=$NAMESPACE tracing=$TRACING logging=$LOGGING sidecars=$SIDECARS virtualService=$VIRTUAL_SERVICE canary=$CANARY externalService=$EXTERNAL_FRONTEND_SERVICE hpa=$HPA"

# Check if the first playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run deploy-argocd.yaml"
    exit 1
fi

# Run the prometheus-grafana playbook
ansible-playbook prometheus-grafana.yml --extra-vars "tracing=$TRACING logging=$LOGGING grafana_smtp_user=$GRAFANA_SMTP_USER grafana_smtp_password=$GRAFANA_SMTP_PASSWORD grafana_smtp_host=$GRAFANA_SMTP_HOST"

# Check if the second playbook ran successfully
if [ $? -ne 0 ]; then
    echo "Failed to run prometheus-grafana.yml"
    exit 1
fi

echo "All playbooks ran successfully"