#!/bin/bash

declare -ga portal_images=("litmusportal-frontend" "litmusportal-server" "litmusportal-auth-server")

declare -ga backend_images=("chaos-operator" "chaos-runner" "chaos-exporter" "go-runner" "litmusportal-event-tracker" "litmusportal-subscriber")

declare -ga workflow_images=("curl:latest" "k8s:latest" "litmus-checker:latest" "workflow-controller:v3.2.3" "argoexec:v3.2.3" "mongo:4.2.8")

## Function to wait for a Given Endpoint to be active
function wait_for_url(){
    wait_period=0
    URL=$1
    # Waiting for URL to be active
    until $(curl --output /dev/null --silent --head --fail $URL); do
    wait_period=$(($wait_period+10))
    if [ $wait_period -gt 300 ];then
       echo "[Info]: The frontend URL couldn't come in active state in 5 minutes, exiting now.."
       exit 1
    else
       printf '.'
       sleep 5
    fi
done
}

## Function to wait for loadbalancer to assigned to a service in a given namespace
function wait_for_loadbalancer(){
    # Variable to store LoadBalancer IP
    IP="";
    Namespace=$2
    SVC=$1
    # Variable to store waiting time for getting IP
    wait_period=0

    # Waiting for LoadBalancer assignment for svc 
    while [ -z $IP ]; 
    do
    wait_period=$(($wait_period+10))
        if [ $wait_period -gt 300 ];then
        echo "[Error]: Couldn't get LoadBalancer IP in 5 minutes, exiting now.."
        exit 1
        else
        echo "[Info]: Waiting for loadBalancer end point..."; 
        IP=$(kubectl get services ${SVC} -n ${Namespace} -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        echo "IP=${IP}"
        sleep 10 
        fi
    done; 
}

## Function to wait for ingress to get an address
function wait_for_ingress(){
    # Variable to store ingress address
    IP="";
    Namespace=$2
    Ingress=$1
    # Variable to store waiting time for getting IP
    wait_period=0

    # Waiting for address assignment for ingress 
    while [ -z $IP ]; 
    do
    wait_period=$(($wait_period+10))
        if [ $wait_period -gt 300 ];then
        echo "[Error]: Couldn't get the Ingress address in 5 minutes, exiting now..."
        exit 1
        else
        echo "[Info]: Waiting for ingress's end point..."; 
        IP=$(eval "kubectl get ing ${Ingress} -n ${Namespace} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'" | awk '{print $1}');
        echo "IP = ${IP}"
        sleep 10 
        fi
    done; 
}


function get_last_nth_release(){
    release_no=${1}
    tail=$(expr ${release_no} - 1)
    curl --silent "https://api.github.com/repos/litmuschaos/litmus-go/releases" |
    grep -m${release_no} '"tag_name":' |
    tail -n${tail} |                                          
    sed -E 's/.*"([^"]+)".*/\1/'
}
                        

## Function to list requested resources in given namespaces
function show_resources(){
    resource_type=$1
    namespace=$2
    kubectl get $resource_type -n $namespace
}

## Function to wait for all pods to be active in a given namespace for given timeout
function wait_for_pods(){
    namespace=$1
    timeout="$2s" # Added "s" for seconds
    kubectl wait --for=condition=Ready pods --all --namespace ${namespace} --timeout=720s
    kubectl get pods -n ${namespace}
}

## Function for verifying deployment
function verify_deployment(){
    deployment=$1
    namespace=$2

    RETRY=0; RETRY_MAX=40;

    while [[ $RETRY -lt $RETRY_MAX ]]; do
        DEPLOYMENT_LIST=$(eval "kubectl get deployments -n ${namespace} | awk '/$deployment /'" | awk '{print $1}') # list of multiple deployments when starting with the same name
        if [[ -z "$DEPLOYMENT_LIST" ]]; then
        RETRY=$((RETRY+1))
        echo "Retry: ${RETRY}/${RETRY_MAX} - Deployment not found - waiting 15s"
        sleep 15
        else
        echo "[Info]: Found deployment ${deployment} in namespace ${namespace}: ${DEPLOYMENT_LIST} ✓"
        break
        fi
    done

    if [[ $RETRY == "$RETRY_MAX" ]]; then
        print_error "[Error]: Could not find deployment ${deployment} in namespace ${namespace}"
        exit 1
    fi

}

## Function for verifying pod in a given namespace
function verify_pod(){
    pod=$1
    namespace=$2
    POD=$(eval "kubectl get pods -n ${namespace} | awk '/${pod}/'")
    if [[ -z "$POD" ]];then
        echo "[Error]: $pod pod not found in $namespace namespace"
        exit 1
    else
        echo "[Info]: $pod pod found in $namespace namespace ✓"
    fi
}

## Function to verify namespace
function verify_namespace(){
    namespace=$1
    NS=$(eval "kubectl get ns | awk '/${namespace}/'")
    if [[ -z "$NS" ]];then
        echo "[Error]: $namespace Namespace not found"
        exit 1
    else
        echo "[Info]: $namespace namespace found ✓"
    fi 
}

## Function to update images in portal manifests, Currently specific to Portal Only
function manifest_image_update(){
    control_plane_version=$1
    core_components_version=$2
    manifest_name=$3
    i=1

    echo -e "\n[Info]: portal component images ...\n"
    for val in ${portal_images[@]}; do
        echo "${i}. litmuschaos/${val}:${control_plane_version}"
        sed -i -e "s|litmuschaos/${val}:.*|litmuschaos/${val}:${control_plane_version}|g" $manifest_name
        i=$((i+1))
    done

    echo -e "\n[Info]: backend component images ...\n"
    for val in ${backend_images[@]}; do
        echo "${i}. litmuschaos/${val}:${core_components_version}"
        sed -i -e "s|\"litmuschaos/${val}:.*\"|\"litmuschaos/${val}:${core_components_version}\"|g" $manifest_name
        i=$((i+1))
    done
}

## Function to verify image for a deployment in given namespace
function verify_deployment_image(){
    image=$1
    deployment=$2
    namespace=$3
    IMAGE=$(eval "kubectl get deployment ${deployement} -n ${namespace} -o=jsonpath='{$.spec.template.spec.containers[:1].image}'")
    if [[ "$image" == "$IMAGE" ]];then
        echo "$deployment deployment is not having the image ${image}"
        exit 1
    else 
        echo "$deployment deployment with image ${image} verified ✓"
    fi
}

## Function to verify all given deployments(comma-separated) in a given namespace
function verify_all_components(){
    components=$1
    namespace=$2
    echo "Verifying all required Deployments"

    for i in $(echo $components | sed "s/,/ /g")
    do
        verify_deployment ${i} ${namespace}
    done
}

# Function to setup Ingress in given namespace for ChaosCenter
function setup_ingress(){
    namespace=$1
    # Updating the svc to ClusterIP
    kubectl patch svc litmusportal-frontend-service -n ${namespace} -p '{"spec": {"type": "ClusterIP"}}'
    kubectl patch svc litmusportal-server-service -n ${namespace} -p '{"spec": {"type": "ClusterIP"}}'

    # Enabling Ingress in Portal
    kubectl set env deployment/litmusportal-server -n ${namespace} --containers="graphql-server" INGRESS="true"

    # Installing ingress-nginx
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install my-ingress-nginx ingress-nginx/ingress-nginx --version 3.33.0 --namespace ${namespace}

    kubectl get pods -n ${namespace}

    wait_for_pods ${namespace} 360

    # Applying Ingress Manifest for Accessing Portal
    kubectl apply -f litmus/ingress.yml -n ${namespace}
    wait_for_ingress litmus-ingress ${namespace}
}

# Function to get Access point of ChaosCenter based on Service type(mode) deployed in given namespace
function get_access_point(){
    namespace=$1
    accessType=$2

    if [[ "$accessType" == "LoadBalancer" ]];then

        kubectl patch svc litmusportal-frontend-service -p '{"spec": {"type": "LoadBalancer"}}' -n ${namespace}
        export loadBalancer=$(kubectl get services litmusportal-frontend-service -n ${namespace} -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        wait_for_pods ${namespace} 360
        wait_for_loadbalancer litmusportal-frontend-service ${namespace}
        export loadBalancerIP=$(kubectl get services litmusportal-frontend-service -n ${namespace} -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        export AccessURL="http://$loadBalancerIP:9091"
        wait_for_url $AccessURL
        echo "URL=$AccessURL" >> $GITHUB_ENV

    elif [[ "$acessType" == "Ingress" ]];then

        setup_ingress ${namespace}
        # Ingress IP for accessing Portal
        export AccessURL=$(kubectl get ing litmus-ingress -n ${namespace} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' | awk '{print $1}')
        echo "URL=http://$AccessURL" >> $GITHUB_ENV

    else 
        # By default NodePort will be used. 
        export NODE_NAME=$(kubectl -n ${namespace} get pod  -l "component=litmusportal-frontend" -o=jsonpath='{.items[*].spec.nodeName}')
        export NODE_IP=$(kubectl -n ${namespace} get nodes $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        export NODE_PORT=$(kubectl -n ${namespace} get -o jsonpath="{.spec.ports[0].nodePort}" services litmusportal-frontend-service)
        export AccessURL="http://$NODE_IP:$NODE_PORT"
        echo "URL=$AccessURL" >> $GITHUB_ENV

    fi
}

function registry_update(){
    new_registry=$1
    manifest=$2
    sed -i -e "s|litmuschaos/litmusportal-frontend|$new_registry/litmusportal-frontend|g" $manifest
    sed -i -e "s|litmuschaos/litmusportal-server|$new_registry/litmusportal-server|g" $manifest
    sed -i -e "s|litmuschaos/litmusportal-auth-server|$new_registry/litmusportal-auth-server|g" $manifest
    sed -i -e "s|litmuschaos/curl|$new_registry/curl|g" $manifest
    sed -i -e "s|litmuschaos/mongo|$new_registry/mongo|g" $manifest    
}

# This function will pull the image, save it as tar & deletes the pulled image for saving memory consumption
function chaos_center_tar_maker(){
    assets_path=$1
    control_plane_version=$2
    core_components_version=$3

    i=1

    echo -e "\n[Info]: pulling portal component images ...\n"
    for val in ${portal_images[@]}; do
        echo -e "\n[Info]: ${i}. litmuschaos/${val}:${control_plane_version}"
        image_name="litmuschaos/${val}:${control_plane_version}"
        tar_maker $image_name "$assets_path/${i}.tar.gz"
        i=$((i+1))
    done

    echo -e "\n[Info]: pulling backend component images ...\n"
    for val in ${backend_images[@]}; do
        echo -e "\n[Info]: ${i}. litmuschaos/${val}:${core_components_version}"
        image_name="litmuschaos/${val}:${core_components_version}"
        tar_maker $image_name "$assets_path/${i}.tar.gz"
        i=$((i+1))
    done

    echo -e "\n[Info]: pulling other images ...\n"
    for val in ${workflow_images[@]}; do
        echo -e "\n[Info]: ${i}. litmuschaos/${val}"
        image_name="litmuschaos/${val}"
        tar_maker $image_name "$assets_path/${i}.tar.gz"
        i=$((i+1))
    done
    
}

tar_maker(){
    image_name=$1
    assetsPath=${2}
    docker pull -q ${image_name} && docker save ${image_name} | gzip > ${assetsPath} && docker image rm ${image_name}
}