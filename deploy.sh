#!/bin/bash

# Exit script immediately when any command fails
set -e
base_dir="$HOME/ws/NoQ"
orchestra_dir="$base_dir/noq-orchestra/kubernetes"
docker_registry_port=5000

back_end_deployment_file=${orchestra_dir}/back-end-deployment.yml
back_end_image_version=$2
back_end_image="localhost:$docker_registry_port/noq-back-end:$2"

front_end_deployment_file=${orchestra_dir}/front-end-deployment.yml
front_end_image_version=$3
front_end_image="localhost:$docker_registry_port/noq-front-end:$front_end_image_version"

database_configmap_file=${orchestra_dir}/database-configmap.yml
database_deployment_file=${orchestra_dir}/database-deployment.yml

STAGING="STAGING"
PRODUCTION="PRODUCTION"

# Check input parameters
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "$0 <ENVIRONMENT> <BACK_END_VERSION> <FRONT_END_VERSION>"
    echo "<ENVIRONMENT> must be in {${STAGING}, ${PRODUCTION}}"
    echo "Example of valid version: 'v1.0.0'"
    exit 1
fi

if [ $1 != $STAGING ] && [ $1 != $PRODUCTION ];
then
    echo "Invalid environment, valid parameters: {${STAGING}, ${PRODUCTION}}"
    exit 1
fi


############################################
# Prepare yml files for desired environment
############################################
PORT_PATTERN="<<EXTERNAL_PORT>>"
BACK_END_VERSION_PATTERN="<<BACK_END_VERSION>>"

# Back end yml
BACK_END_VERSION=$2
BACK_END_STAGING_PORT="31002"
BACK_END_PRODUCTION_PORT="32002"
BACK_END_PORT=$BACK_END_STAGING_PORT

if [ $1 == $STAGING ];
then
    BACK_END_PORT=$BACK_END_STAGING_PORT
elif [ $1 == $PRODUCTION ];
then
    BACK_END_PORT=$BACK_END_PRODUCTION_PORT
fi

sed -i -e "s/${PORT_PATTERN}/${BACK_END_PORT}/g" ${back_end_deployment_file}
sed -i -e "s/${BACK_END_VERSION_PATTERN}/${back_end_image_version}/g" ${back_end_deployment_file}


# Front end yml
FRONT_END_VERSION=$3
FRONT_END_STAGING_PORT="31001"
FRONT_END_PRODUCTION_PORT="32001"
FRONT_END_PORT=$FRONT_END_STAGING_PORT

FRONT_END_VERSION_PATTERN="<<FRONT_END_VERSION>>"

if [ $1 == $STAGING ];
then
    FRONT_END_PORT=$FRONT_END_STAGING_PORT
    FRONT_END_NODE_PORT=$FRONT_END_STAGING_NODE_PORT
elif [ $1 == $PRODUCTION ];
then
    FRONT_END_PORT=$FRONT_END_PRODUCTION_PORT
    FRONT_END_NODE_PORT=$FRONT_END_PRODUCTION_NODE_PORT
fi

sed -i -e "s/${PORT_PATTERN}/${FRONT_END_PORT}/g" ${front_end_deployment_file}
sed -i -e "s/${FRONT_END_VERSION_PATTERN}/${front_end_image_version}/g" ${front_end_deployment_file}


# Database yml
DATABASE_NAME_PATTERN="<<DATABASE_NAME>>"
DATABASE_NAME="noq_mstaging"
if [ $1 == $STAGING ];
then
    DATABASE_NAME="noq_staging"
elif [ $1 == $PRODUCTION ];
then
    DATABASE_NAME="noq_prod"
fi

sed -i -e "s/${DATABASE_NAME_PATTERN}/${DATABASE_NAME}/g" ${database_configmap_file}


DATABASE_PORT_PATTERN="<<DATABASE_PORT>>"
DATABASE_PORT="3306"
if [ $1 == $STAGING ];
then
    DATABASE_PORT="3307"
elif [ $1 == $PRODUCTION ];
then
    DATABASE_PORT="3308"
fi

sed -i -e "s/${DATABASE_PORT_PATTERN}/${DATABASE_PORT}/g" ${database_deployment_file}
sed -i -e "s/${DATABASE_PORT_PATTERN}/${DATABASE_PORT}/g" ${back_end_deployment_file}


#############
# Test tools
#############
docker -v
k3s check-config
sudo kubectl version
git --version
yes --version
gawk --version
tail --version


# Build back-end image
back_end_code_dir="${base_dir}/noq-back-end"
back_end_image=noq-back-end:${BACK_END_VERSION}
back_end_image_registry=localhost:$docker_registry_port/$back_end_image
cd $back_end_code_dir
./gradlew build -x test
docker build -f ./docker/DockerfileRun -t $back_end_image .
docker tag $back_end_image $back_end_image_registry
docker push $back_end_image_registry

# Database configuration
cd $orchestra_dir
sudo kubectl apply -f secrets.yml
sudo kubectl apply -f database-configmap.yml
sudo kubectl apply -f database-deployment.yml

# Test database
sudo kubectl rollout status deployment mysql
database_pod_state=`sudo kubectl get po --sort-by=.status.startTime | tail -1 | gawk {'print $1" " $3'} | column -t | cut -d " " -f 3`
if [ "$database_pod_state" != "Running" ]; then
    echo "[ERROR] database pod not running"
    sudo kubectl get pods; echo ""
    exit 1
fi


# Test persistent volume claim status
pvc_status=`sudo kubectl get pvc | grep database-pv-claim | gawk {'print $2'} | column -t`
if [ "$pvc_status" != "Bound" ]; then
    echo "[ERROR] Persistent  pod not running"
    kubectl get pvc; echo ""
    exit 1
fi

# Deploy back-end image
cd $orchestra_dir
sudo kubectl apply -f back-end-deployment.yml

# Check deployment and revert it if error
if ! sudo kubectl rollout status deployment noq-back-end; then
    sudo kubectl rollout undo deployment noq-back-end
    sudo kubectl rollout status deployment noq-back-end
    exit 1
fi

# Build front-end image
front_end_code_dir="$base_dir/noq-front-end"
front_end_image=noq-front-end:${FRONT_END_VERSION}
front_end_image_registry=localhost:$docker_registry_port/$front_end_image
cd $front_end_code_dir
npm install
npm --max_old_space_size=4096 run ng build

docker build -f ./docker/DockerfileRun -t $front_end_image .
docker tag $front_end_image $front_end_image_registry
docker push $front_end_image_registry


# Deploy front-end image
cd $orchestra_dir
sudo kubectl apply -f front-end-deployment.yml
# Check deployment and revert it if error
if ! sudo kubectl rollout status deployment noq-back-end; then
    sudo kubectl rollout undo deployment noq-back-end
    sudo kubectl rollout status deployment noq-back-end
    exit 1
fi


# Delete tags of user registry images
docker rmi $back_end_image_registry
docker rmi $front_end_image_registry
# Remove dangling images and stopped containers
yes | docker system prune


