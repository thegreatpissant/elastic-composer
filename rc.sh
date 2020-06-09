#!/bin/bash

set -xe

# The run command for this setup

# Source our .env file
. .env

DOCKER_COMPOSE=/usr/local/bin/docker-compose
SYSTEM_NAMES="$ELASTIC1_HOSTNAME $ELASTIC2_HOSTNAME $ELASTIC3_HOSTNAME $KIBANA_HOSTNAME"

create_data_dir() {
# Create the data dirs on each host
for i in $SYSTEM_NAMES; do
DATADIR=/$ELASTIC_STACK_NAME/$i
ssh $i "mkdir -p $DATADIR"
ssh $i "chmod 777 $DATADIR"
ssh $i "chcon -Rt svirt_sandbox_file_t $DATADIR"
done
}

create_certs_dir() {
#  Create the directory the certs will be placed in.
CERTSDIR=/$ELASTIC_STACK_NAME/$CERTS_VOLUME_LOCATION
for i in $SYSTEM_NAMES; do
ssh $i "mkdir -p $CERTSDIR"
ssh $i "chcon -Rt svirt_sandbox_file_t $CERTSDIR"
done
}

generate_docker_compose_configs() {
# generate the docker-compose files from our .env settings.
$DOCKER_COMPOSE -f create-certs-template.yml config > create-certs.yml
$DOCKER_COMPOSE -f elastic-docker-tls-template.yml config > elastic-docker-tls.yml
}

generate_certs() {
# generate the certs, we can use compose for this.
$DOCKER_COMPOSE -f create-certs.yml run --rm create_certs
}

copy_certs() {
# copy certs to other systems
for i in $SYSTEM_NAMES; do
  echo "Copying certs to: $i"
  scp -r /$ELASTIC_STACK_NAME/$CERTS_VOLUME_NAME $i:/$ELASTIC_STACK_NAME/
  echo "changing selinux labels"
  ssh $i "chcon -Rt svirt_sandbox_file_t /$ELASTIC_STACK_NAME"
done
}

deploy_stack() {
# deploy the stack
docker stack deploy -c elastic-docker-tls.yml jlastic
}

clean_remotes() {
# Remove the remote elastic swarm directories.
if [ -z $ELASTIC_STACK_NAME ]; then
echo "Clean remotes"
echo "Stack name is empty."
exit
fi
for i in $SYSTEM_NAMES; do
  ssh $i "rm -fr /$ELASTIC_STACK_NAME"
done
}

grab_remotes() {
# Get the data directories of the remote elastic swarm directories
DATADIR=data_`date +"%s"`
for i in $SYSTEM_NAMES; do
  mkdir -p $DATADIR/$i
  scp -r $i:/$ELASTIC_STACK_NAME ./$DATADIR/$i/ 
done
}

remove_stack() {
# Stop the stack and remove it
docker stack rm $ELASTIC_STACK_NAME
}

case $1 in
  "deploy_stack")
    deploy_stack
  ;;
  "clean_remotes")
    clean_remotes
  ;;
  "create_data_dir")
    create_data_dir
  ;;
  "create_certs_dir")
    create_certs_dir
  ;;
  "copy_certs")
    create_certs_dir
    copy_certs
  ;;
  "generate_certs")
    generate_certs
  ;;
  "compose_configs")
    generate_docker_compose_configs
  ;;
  "grab_remotes")
    grab_remotes
  ;;
  "scratch")
    remove_stack
    clean_remotes
    create_data_dir
    create_certs_dir
    generate_docker_compose_configs
    generate_certs
    copy_certs
    deploy_stack
  ;;
  *)
  echo "Unknown option"
cat << EOI
deploy_stack - Deploy the stack

clean_remotes - clean out the remotes certs directory

create_data_dir - create the data dir on each system

create_certs_dir - create the certs dir on each system

copy_certs - copy over the certs to the remotes 

generate_certs - Generate the certs

compose_configs - Generate docker compose configurations

grab_remotes - get all the remote datafiles

EOI
  ;;
esac;
