#!/bin/bash
set -e

source utils.sh

# Import pre-installed images
for file in ./*.tar; do
  docker load <$file
done

# Litmus-Portal Works starts from here
local_registry="localhost:5000"
namespace="litmus"
version="ci"

docker tag litmuschaos/litmusportal-frontend:ci ${local_registry}/litmusportal-frontend:ci
docker tag litmuschaos/litmusportal-server:ci ${local_registry}/litmusportal-server:ci
docker tag litmuschaos/litmusportal-auth-server:ci ${local_registry}/litmusportal-auth-server:ci

registry_update "${local_registry}" litmus-portal-setup.yml

kubectl apply -f litmus-portal-setup.yml

kubectl describe nodes 

sleep 5

kubectl get pods -A

kubectl get pods -n litmus

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
