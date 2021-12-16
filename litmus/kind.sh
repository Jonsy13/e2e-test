#!/bin/bash
set -e

source utils.sh

echo "Setting up KIND cluster"

docker load -i node.tar
docker load -i registry.tar

docker load -i litmusportal-frontend.tar
docker load -i litmusportal-server.tar
docker load -i litmusportal-auth-server.tar

set -o errexit

# create registry container unless it already exists
reg_name='kind-registry'
reg_port='5000'
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --image kindest/node:v1.21.1 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:5000"]
EOF

# connect the registry to the cluster network
# (the network may already be connected)
docker network connect "kind" "${reg_name}" || true

# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

local_registry="localhost:${reg_port}"

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