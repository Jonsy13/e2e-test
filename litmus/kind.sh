#!/bin/bash
set -e

source utils.sh

docker network inspect kind

# Import pre-installed images
echo -e "\n---------------Loading All Images for ChaosCenter---------------\n"
for file in ./*.tar; do
  docker load -q <$file
done

# Litmus-Portal Works starts from here
local_registry="localhost:5000"
namespace="litmus"
version="ci"

echo -e "\n---------------Tagging All Images for ChaosCenter for local registry---------------\n"

docker tag litmuschaos/litmusportal-frontend:ci ${local_registry}/litmusportal-frontend:ci
docker tag litmuschaos/litmusportal-server:ci ${local_registry}/litmusportal-server:ci
docker tag litmuschaos/litmusportal-auth-server:ci ${local_registry}/litmusportal-auth-server:ci
docker tag litmuschaos/curl:latest ${local_registry}/curl:latest
docker tag litmuschaos/mongo:4.2.8 ${local_registry}/mongo:4.2.8
docker tag jonsy13/e2e:ci ${local_registry}/e2e:ci


echo -e "\n---------------Pushing All Images for ChaosCenter to local registry------------------\n"

docker push -q ${local_registry}/litmusportal-frontend:ci
docker push -q ${local_registry}/litmusportal-server:ci
docker push -q ${local_registry}/litmusportal-auth-server:ci
docker push -q ${local_registry}/curl:latest
docker push -q ${local_registry}/mongo:4.2.8
docker push -q ${local_registry}/e2e:ci

echo -e "\n---------------Updating Registry in manifest-----------------------------------------\n"
registry_update "${local_registry}" litmus-portal-setup.yml

echo -e "\n---------------Applying Manifest-----------------------------------------------------\n"
kubectl apply -f litmus-portal-setup.yml

kubectl describe nodes 

sleep 10

kubectl get pods -A

kubectl get pods -n litmus

kubectl describe pods -n litmus

echo -e "\n---------------Pods running in ${namespace} Namespace---------------\n"
kubectl get pods -n ${namespace}

echo -e "\n---------------Waiting for all pods to be ready---------------\n"
# Waiting for pods to be ready (timeout - 360s)
wait_for_pods ${namespace} 360

# Getting access point for ChaosCenter
export NODE_NAME=$(kubectl -n ${namespace} get pod  -l "component=litmusportal-frontend" -o=jsonpath='{.items[*].spec.nodeName}')
export NODE_IP=$(kubectl -n ${namespace} get nodes $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
export NODE_PORT=$(kubectl -n ${namespace} get -o jsonpath="{.spec.ports[0].nodePort}" services litmusportal-frontend-service)
export AccessURL="http://$NODE_NAME:$NODE_PORT"

docker network inspect kind

docker run --net kind litmuschaos/curl:latest $AccessURL

kubectl apply -f test.yml

POD=$(kubectl get pod -n litmus -l purpose=testing -o jsonpath="{.items[0].metadata.name}")

wait_for_pods ${namespace} 360

kubectl logs -f ${POD} -n litmus

docker network inspect kind
