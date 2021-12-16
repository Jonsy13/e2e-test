#!/bin/bash
set -e

source utils.sh

docker load -i litmusportal-frontend.tar
docker load -i litmusportal-server.tar
docker load -i litmusportal-auth-server.tar

set -o errexit

# Litmus-Portal Works starts from here

namespace="litmus"
version="ci"

docker tag litmuschaos/litmusportal-frontend:ci ${local_registry}/litmusportal-frontend:ci
docker tag litmuschaos/litmusportal-server:ci ${local_registry}/litmusportal-server:ci
docker tag litmuschaos/litmusportal-auth-server:ci ${local_registry}/litmusportal-auth-server:ci

registry_update "${local_registry}" litmus-portal-setup.yml

kubectl apply -f litmus-portal-setup.yml

echo -e "\n---------------Pods running in ${namespace} Namespace---------------\n"
kubectl get pods -n ${namespace}

echo -e "\n---------------Waiting for all pods to be ready---------------\n"
# Waiting for pods to be ready (timeout - 360s)
wait_for_pods ${namespace} 360

echo -e "\n------------- Verifying Namespace, Deployments, pods and Images for Litmus-Portal ------------------\n"
# Namespace verification
verify_namespace ${namespace}

# Deployments verification
verify_all_components litmusportal-frontend,litmusportal-server ${namespace}

# Pods verification
verify_pod litmusportal-frontend ${namespace}
verify_pod litmusportal-server ${namespace}
verify_pod mongo ${namespace}

# Images verification
verify_deployment_image $version litmusportal-frontend ${namespace}
verify_deployment_image $version litmusportal-server ${namespace}


echo -e "\n---------------Pods running in ${namespace} Namespace---------------\n"
kubectl get pods -n ${namespace}

exec "$@"