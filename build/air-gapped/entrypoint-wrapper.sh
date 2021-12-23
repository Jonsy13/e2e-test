#!/bin/bash
set -e
set -o errexit

echo -e "[Info]: -----------------------Setting up KIND cluster-----------------------"

# Start docker service in background
/usr/local/bin/dockerd-entrypoint.sh &

# Wait that the docker service is up
while ! docker info; do
  echo "Waiting docker..."
  sleep 3
done

# Import pre-installed images
for file in ./assets/*.tar; do
  docker load -q <$file
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

echo -e "[Info]: -----------------------Setting up Local Registry -----------------------"
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

echo -e "[Info]: -----------------------Local Registry created: ${local_registry} -----------------------"

# Importing provided images into local registry
echo -e "\n[Info]: --------------- Loading all provided images to local registry---------------\n"
for file in ./registry/*.tar.gz; do
  loaded=$(docker load -q <$file)
  full_image_name=$(echo ${loaded:14})
  array=(`echo $full_image_name | sed 's|/|\n|g'`)
  image_with_tag=${array[-1]}
  repo=${array[-2]}
  docker tag ${repo}/${image_with_tag} ${local_registry}/${image_with_tag}
  docker push -q ${local_registry}/${image_with_tag} && docker rm ${repo}/${image_with_tag}
done

exec "$@"