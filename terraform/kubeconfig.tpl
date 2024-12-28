apiVersion: v1
kind: Config
preferences: {}
current-context: ${cluster_name}

clusters:
- cluster:
    certificate-authority-data: ${cluster_ca}
    server: https://${endpoint}
  name: ${cluster_name}

contexts:
- context:
    cluster: ${cluster_name}
    user: ${cluster_name}
  name: ${cluster_name}

users:
- name: ${cluster_name}
  user:
    token: ${client_token}