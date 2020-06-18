This will deploy a xpack security enabled cluster of three elastic nodes, kibana, and logstash, to a set of systems in a docker swarm configuration.  It was originally based on the elastic docker compose files and other references cited below.

I use this to deploy a test system on my home network and collect logs off my pfsense system (I highly recommend you do the same!!).  Instructions are included for that setup.



*This version exposes passwords in the **env** of each docker container.  Working on moving this to a more secure option.*

Instructions:

- Identify 5 nodes for the deployment. *I setup a single image that can ssh key exchange with itself and then make a copy of that vm for each node.*

- Define one of the nodes as the docker swarm master, maybe elastic-1

- Setup a docker swarm of 5 systems.
	- elastic-1
	- elastic-2
	- elastic-3
	- kibana
	- logstash

- Ensure the swarm master has root ssh key access to all other nodes in swarm

- Set variables in the .env file
```
# .env file example
COMPOSE_PROJECT_NAME=es
#  Directory in the containers that will contain certificates
CERTS_DIR=/usr/share/elasticsearch/config/certificates
#  Version of docker images to use
VERSION=7.7.0
#  Master Swarm node name this script is run on, used when running the create_certs containers
MASTER_NODE_HOSTNAME=elastic-1
#  Define the swarm hostnames
ELASTIC1_HOSTNAME=elastic-1
ELASTIC2_HOSTNAME=elastic-2
ELASTIC3_HOSTNAME=elastic-3
KIBANA_HOSTNAME=kibana
LOGSTASH_HOSTNAME=logstash
#  Define the stack names
ELASTIC_STACK_NAME=jlastic
KIBANA_STACK_NAME=jlastic-kibana
LOGSTASH_STACK_NAME=jlastic-logstash
CERTS_STACK_NAME=certstack
#  Docker volume certificate subdirectory name, will be under the $ELASTIC_STACK_NAME directory
CERTS_VOLUME_NAME=certstack_certs
```

- Running `rc.sh` will print out each step that is taken to deploy, so you can test each step separately at first.
- Or, run './rc.sh scratch' to run through the whole cleanup and deployment.  Rerunning './rc.sh scratch' will remove all the original data so make sure thats what you want to do.
- `./rc.sh grab-remotes` will grab the remote system data and copy it locally, but make sure you have room for it.
- Running `./rc.sh scratch` will show you the information required to login to kibana.
- Port `9200/tcp` will be exposed to all nodes for beat integration
- Port `5514/udp` will be exposed for the pfsense firewall log setup below.


## Integrating pfsense firewall logs

- Setup the nodes as defined above.

- Setup your pfsense firewall logging as per https://github.com/thegreatpissant/logstockpile/blob/master/README.md

- Setup the logstash `main` pipeline; *Management->Logstash->Pipelines->Create pipeline*
  -  Enter "**main**" as the `Pipeline ID` and paste the contents of the pipeline configuration at https://raw.githubusercontent.com/thegreatpissant/logstockpile/master/pfsense.conf
  - In the **output** section of the pasted pipeline, uncomment and update the elastic-composer fields with your information for **user:elastic** and the **password** that was supplied when you setup the stack.


## Random Notes that are left for reference

stack name is perpended to the volumes.

Generate the create-certs-full.yml config file

`/usr/local/bin/docker-compose -f create-certs.yml config > create-certs-full.yml`

Generate the certs, place in the ~CERTS_VOLUME_LOCATION=/jlastic/certs~ directory

`/usr/local/bin/docker-compose -f create-certs.yml run --rm create_certs`

.env files are note recognized with docker stack 

`docker stack deploy -c create-certs-.yml certstack`

`/usr/local/bin/docker-compose -f create-certs.yml config`

:Z to the volume name allows for selinux support

create the certs volume
push out to the other systems via scp
run the swarm


## Generating the kibana password and elastic user login.

## This command will generate the password on the elastic node.
docker exec <es01-container-id> /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200"

## For example 
```
docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200"

Changed password for user apm_system
PASSWORD apm_system = jtwYFbURz8gAN5HHlMqE

Changed password for user kibana
PASSWORD kibana = AMhSLYd9VwxtZuOhxtgy

Changed password for user logstash_system
PASSWORD logstash_system = BW0OkZM480DqzFK7DHuu

Changed password for user beats_system
PASSWORD beats_system = C88bk9OT6wZTRcZcIs0p

Changed password for user remote_monitoring_user
PASSWORD remote_monitoring_user = UbUEVMXu1CYV67GBHp1g

Changed password for user elastic
PASSWORD elastic = fizCbXxNPjN5By0qG7d6
```

Replace the 'kib01' service's 'ELASTIC_PASSWORD' value to the 'PASSWORD kibana' Field In the docker compose template "elastic-docker-tls.yml", that file was generated during setup.

Use user:elastic, password:'<PASSWORD elastic from above>' When loging into the kibana interface.

Instructions from https://www.elastic.co/guide/en/elastic-stack-get-started/current/get-started-docker.html#:~:text=elastic%2Ddocker%2Dtls.,distributed%20deployment%20with%20multiple%20hosts.

docker exec `docker ps | grep es01| awk '{ print $1 }'` /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200"
docker stack deploy -c elastic-docker-tls.yml jlastic
