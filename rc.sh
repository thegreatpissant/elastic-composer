#!/bin/bash

set -x

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

create_dirs() {
create_certs_dir
create_data_dir
}

generate_docker_compose_configs() {
# generate the docker-compose files from our .env settings.
$DOCKER_COMPOSE -f create-certs-template.yml config > create-certs.yml
$DOCKER_COMPOSE -f elastic-docker-tls-template.yml config > elastic-docker-tls.yml
$DOCKER_COMPOSE -f kibana-docker-tls-template.yml config > kibana-docker-tls.yml
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
done
}

update_dir_perms() {
for i in $SYSTEM_NAMES; do
  DATADIR=/$ELASTIC_STACK_NAME/$i
  echo "changing selinux labels"
  ssh $i "chcon -Rt svirt_sandbox_file_t /$ELASTIC_STACK_NAME"
  ssh $i "chmod 777 $DATADIR"
done
}

deploy_stack() {
# deploy the stack
docker stack deploy -c elastic-docker-tls.yml $ELASTIC_STACK_NAME
}

deploy_kibana() {
# deploy kibana stack
docker stack deploy -c kibana-docker-tls.yml $KIBANA_STACK_NAME
echo "Kibana deployed, wait 20 seconds for it to come up"
echo "Try https://$MASTER_NODE_HOSTNAME:5601"
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

generate_network() {
#  Create the overlay network used by stack and kibana
docker network create --driver=overlay --attachable elastic
}

update_passwords() {
#  Update the elastic passwords
GOTPASS=1
while [ $GOTPASS -ne 0 ]; do
	docker exec `docker ps | grep es01| awk '{ print $1 }'` /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200" > $ELASTIC_STACK_NAME-passwords
	GOTPASS=$?
	if [ $GOTPASS -ne 0 ]; then
		echo "Elastic password not changed yet, sleeping and trying again"
		sleep 1
	fi
done
	
KIBANAPASS=$(grep PASSWORD $ELASTIC_STACK_NAME-passwords | grep kibana | awk '{ print $4 }')
ELASTICPASS=$(grep PASSWORD $ELASTIC_STACK_NAME-passwords | grep elastic | awk '{ print $4 }')

sed -i s/CHANGEME/$KIBANAPASS/ ./kibana-docker-tls.yml
echo your kibana login  user:elastic  password:$ELASTICPASS

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
docker stack rm $KIBANA_STACK_NAME
docker network rm elastic
}

case $1 in
  "deploy_stack")
    deploy_stack
  ;;
  "deploy_kibana")
    deploy_kibana
  ;;
  "update_passwords")
    update_passwords
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
  "update_dir_perms")
    update_dir_perms
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
  "generate_network")
    generate_network
  ;;
  "scratch")
    remove_stack
    clean_remotes
    create_data_dir
    create_certs_dir
    generate_docker_compose_configs
    generate_certs
    copy_certs
    update_dir_perms
    generate_network
    deploy_stack
    update_passwords
    deploy_kibana
  ;;
  *)
  echo "Unknown option"
cat << EOI
Commands in execution order

  clean_remotes - clean out the remotes certs directory

  create_data_dir - create the data dir on each system

  create_certs_dir - create the certs dir on each system

  compose_configs - Generate docker compose configurations

  generate_certs - Generate the certs

  copy_certs - copy over the certs to the remotes 

  update_dir_perms - update the directory permisions on files and directories

  generate_network - generate the elastic overlay network

  deploy_stack - Deploy the elastic stack

  - scratch - will run up to this point.
  
  update_passwords - Generate the passwords for this stack (one time success only!!)

  deploy_kibana - Deploy the kibana stack

  grab_remotes - get all the remote datafiles

EOI
  ;;
esac;
