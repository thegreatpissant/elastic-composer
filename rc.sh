#!/bin/bash

# set -x

# The run command shell script (rc.sh)

# Source .env file
. .env

DOCKER_COMPOSE=/usr/local/bin/docker-compose
SYSTEM_NAMES="$ELASTIC1_HOSTNAME $ELASTIC2_HOSTNAME $ELASTIC3_HOSTNAME $KIBANA_HOSTNAME $LOGSTASH_HOSTNAME"

create_data_dir() {
	# Create the data dirs on each host
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		DATADIR=/$ELASTIC_STACK_NAME/$i
		ssh "$i" "mkdir -p $DATADIR"
		ssh "$i" "chmod 777 $DATADIR"
	done
}

create_certs_dir() {
	#  Create the directory the certs will be placed in.
	CERTSDIR=/$ELASTIC_STACK_NAME/$CERTS_VOLUME_LOCATION
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		ssh "$i" "mkdir -p $CERTSDIR"
		ssh "$i" "chcon -Rt svirt_sandbox_file_t $CERTSDIR"
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
	$DOCKER_COMPOSE -f logstash-docker-tls-template.yml config > logstash-docker-tls.yml
}

generate_certs() {
	# generate the certs, we can use compose for this.
	$DOCKER_COMPOSE -f create-certs.yml run --rm create_certs
}

copy_certs() {
	# copy certs to other systems
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		scp -r /$ELASTIC_STACK_NAME/$CERTS_VOLUME_NAME "$i":/$ELASTIC_STACK_NAME/
	done
}

update_dir_perms() {
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		DATADIR=/$ELASTIC_STACK_NAME/$i
		ssh "$i" "chcon -Rt svirt_sandbox_file_t /$ELASTIC_STACK_NAME"
		ssh "$i" "chown -R root:root /$ELASTIC_STACK_NAME"
		ssh "$i" "chmod 777 $DATADIR"
	done
}

deploy_stack() {
	# deploy the stack
	docker stack deploy -c elastic-docker-tls.yml $ELASTIC_STACK_NAME
}

deploy_kibana() {
	# deploy kibana stack
	docker stack deploy -c kibana-docker-tls.yml $KIBANA_STACK_NAME
	echo
	echo "Kibana deployed, wait a minute or two for it to come up"
	echo "Try https://$MASTER_NODE_HOSTNAME:5601"
}

deploy_logstash() {
	# deploy logstash stack
	docker stack deploy -c logstash-docker-tls.yml $LOGSTASH_STACK_NAME
	echo
	echo "logstash deployed"
}

clean_remotes() {
	# Remove the remote elastic swarm directories.
	if [ -z $ELASTIC_STACK_NAME ]; then
		echo "Clean remotes"
		echo "# ERROR Stack name variable is empty."
		exit
	fi
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		ssh "$i" "rm -fr /$ELASTIC_STACK_NAME"
	done
}

generate_network() {
	#  Create the overlay network used by stack and kibana
	docker network create --driver=overlay --attachable --subnet="$DOCKER_NETWORK_SUBNET" --gateway="$DOCKER_NETWORK_GATEWAY" elastic
}

generate_passwords() {
	echo "Updating elastic passwords"
	echo "If this goes on for to long ( >1min) , something is wrong."
	#  Update the elastic passwords
	PASSWORD_FILE=$ELASTIC_STACK_NAME-passwords
	until docker exec "$(docker ps | grep es01| awk '{ print $1 }')" /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200" > $PASSWORD_FILE 2>/dev/null; do
		echo "Elastic Password not changed yet, sleeping and trying again"
		sleep 1
	done

	echo "Setting passwords in docker files"

}

update_passwords() {
  #  Grab the passwords 
  PASSWORD_FILE=$ELASTIC_STACK_NAME-passwords
  KIBANAPASS=$(grep PASSWORD $PASSWORD_FILE | grep 'kibana =' | awk '{ print $4 }')
  ELASTICPASS=$(grep PASSWORD $PASSWORD_FILE | grep 'elastic =' | awk '{ print $4 }')
  # Update templates with the generated passwords.
  sed -i s/CHANGEME/"$KIBANAPASS"/g ./kibana-docker-tls.yml
  sed -i s/CHANGEME_ELASTIC_PASSWORD/"$ELASTICPASS"/ ./logstash-docker-tls.yml

  echo 
  echo "## User information ##"
  echo "###############################################################"
  echo "####################    KIBANA LOGIN     ######################"
  echo "##### user:elastic  password:$ELASTICPASS #####"
  echo "### Generated credentials are saved in file $PASSWORD_FILE  ###"
  echo "##############################################################"
}

grab_remotes() {
	# Get the data directories of the remote elastic swarm directories
	DATADIR=data_$(date +"%s")
	for i in $SYSTEM_NAMES; do
		echo "System name: $i"
		mkdir -p "$DATADIR"/"$i"
		scp -r "$i":/"$ELASTIC_STACK_NAME" ./"$DATADIR"/"$i"/ 
	done
}

remove_stack() {
	# Stop the stack and remove it
	docker stack rm "$ELASTIC_STACK_NAME"
	docker stack rm "$KIBANA_STACK_NAME"
	docker stack rm "$LOGSTASH_STACK_NAME"
	docker network rm elastic
}

# Main
case $1 in
	"remove_stack")
		remove_stack
		;;
	"deploy_stack")
		deploy_stack
		;;
	"deploy_kibana")
		deploy_kibana
		;;
	"deploy_logstash")
		deploy_logstash
		;;
	"generate_passwords")
		generate_passwords
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
		echo
		echo "##  Removing original stack  ##"
		remove_stack

		echo
		echo "##  Cleanining remote systems  ##"
		clean_remotes

		echo
		echo "##  Creating data dirs  ##"
		create_data_dir

		echo
		echo "##  Creating cert dirs  ##"
		create_certs_dir

		echo
		echo "##  Generating docker compose configurations  ##"
		generate_docker_compose_configs

		echo
		echo "##  Generating certificates  ##"
		generate_certs

		echo
		echo "##  Copying certs to systems  ##"
		copy_certs

		echo
		echo "##  Updating permisions and selinux labels  ##"
		update_dir_perms

		echo
		echo "##  Creating docker network  ##"
		generate_network

		echo
		echo "##  Deploying elastic stack ##"
		deploy_stack

		echo
		echo "##  Generating Passwords  ##"
		generate_passwords

		echo
		echo "##  Updating Passwords  ##"
		update_passwords

		echo
		echo "##  Deploying kibana  ##"
		deploy_kibana

		echo
		echo "##  Deploying logstash ##"
		deploy_logstash
		;;
	*)
		echo "Unknown option"
		cat << EOI
Setup and Deployment Commands in execution order

  remove_stack - remove the stack's and elastic overlay network

  clean_remotes - clean out the remotes certs directory

  create_data_dir - create the data dir on each system

  create_certs_dir - create the certs dir on each system

  compose_configs - Generate docker compose configurations

  generate_certs - Generate the certs

  copy_certs - copy over the certs to the remotes 

  update_dir_perms - update the directory permisions on files and directories

  generate_network - generate the elastic overlay network

  deploy_stack - Deploy the elastic stack

  generate_passwords - Generate the passwords for this stack (one time success only!!)

  update_passwords - Update the config files for this stack (one time success only!!)

  deploy_kibana - Deploy the kibana docker stack

  deploy_logstash - Deploy the logstash docker stack

Bulk execution of commands
  scratch - will run all previous commands, setting up the full system

  grab_remotes - get all the remote datafiles

EOI
;;
esac;
