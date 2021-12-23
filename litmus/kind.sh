#!/bin/bash
set -e

source utils.sh

# Litmus-Portal Works starts from here
local_registry="localhost:5000"
namespace="litmus"

# Import pre-installed images
echo -e "\n[Info]: --------------- Loading All Images for ChaosCenter to local registry---------------\n"
for file in ./*.tar.gz; do
  loaded=$(docker load -q <$file)
  full_image_name=$(echo ${loaded:15})
  array=(`echo $full_image_name | sed 's|/|\n|g'`)
  image_with_tag=${array[-1]}
  repo=${array[-2]}
  docker tag ${repo}/${image_with_tag} ${local_registry}/${image_with_tag}
  docker push -q ${local_registry}/${image_with_tag}
done
echo -e "\n[Info]: --------------- Updating Registry in manifest -----------------------------------------\n"
registry_update "${local_registry}" litmus-portal-setup.yml

echo -e "\n[Info]: --------------- Applying Manifest -----------------------------------------------------\n"
kubectl apply -f litmus-portal-setup.yml

echo -e "\n[Info]: --------------- Waiting for 10 sec ----------------------------------------------------\n"
sleep 10

echo -e "\n[Info]: --------------- Pods running in ${namespace} Namespace ---------------\n"
kubectl get pods -n ${namespace}

echo -e "\n[Info]: --------------- Waiting for all pods to be ready ---------------\n"
# Waiting for pods to be ready (timeout - 360s)
wait_for_pods ${namespace} 360

# Getting access point for ChaosCenter
export NODE_NAME=$(kubectl -n ${namespace} get pod  -l "component=litmusportal-frontend" -o=jsonpath='{.items[*].spec.nodeName}')
export NODE_IP=$(kubectl -n ${namespace} get nodes $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
export NODE_PORT=$(kubectl -n ${namespace} get -o jsonpath="{.spec.ports[0].nodePort}" services litmusportal-frontend-service)
export AccessURL="http://$NODE_IP:$NODE_PORT"

# Running Tests
echo -e "\n[Info]: --------------- Starting Tests ---------------\n"
docker run -it --net host -e CYPRESS_BASE_URL=${AccessURL} -e CYPRESS_INCLUDE_TAGS="login" jonsy13/e2e:ci
