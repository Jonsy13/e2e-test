#!/bin/bash
set -e
set -o errexit

echo "Setting up KIND cluster"

# Start docker service in background
/usr/local/bin/dockerd-entrypoint.sh &

# Wait that the docker service is up
while ! docker info; do
  echo "Waiting docker..."
  sleep 3
done

# Import pre-installed images
for file in ./assets/*.tar; do
  docker load <$file
done

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
kind create cluster --image kindest/node:v1.21.1 --config=./kind-config.yml --wait=900s

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

exec "$@"