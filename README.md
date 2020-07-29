This will deploy a xpack security enabled cluster of three Elasticsearch nodes, Kibana, and Logstash, to a set of systems in a docker swarm configuration.  It was originally based on the elastic docker compose files and other references cited below.

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
#  Define the Docker swarm network Paramaters.  Keep in mind that swarm containers can reach outside the network they are on.
#  Yes, these values are from the docker docs. https://docs.docker.com/network/overlay/
DOCKER_NETWORK_SUBNET=10.11.0.0/16
DOCKER_NETWORK_GATEWAY=10.11.0.2
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

- Setup the Logstash `main` pipeline; *Management->Logstash->Pipelines->Create pipeline*
  -  Enter "**main**" as the `Pipeline ID` and paste the contents of the pipeline configuration at https://raw.githubusercontent.com/thegreatpissant/logstockpile/master/pfsense.conf
  - In the **output** section of the pasted pipeline, uncomment and update the elastic-composer fields with your information for **user:elastic** and the **password** that was supplied when you setup the stack.

## Integrating Beats

When setting up your beat products you will have three exposed elastic nodes that can have data sent to them.

Add the generated CA to your systems CA store.

The supplied `.env` file has three hosts that are the host names of the nodes in your swarm.  These hosts will expose their Elasticsearch instance on a unique port number from the others.  In this example `ELASTIC1_HOSTNAME`, `ELASTIC2_HOSTNAME`, and `ELASTIC3_HOSTNAME` as defined in the `.env` file will will be assigned the port number `9200, 9201, 9202` respectively.  Here is an example of the `Elasticsearch output` section to use.

```
#-------------------------- Elasticsearch output ------------------------------
output.elasticsearch:
  # Array of hosts to connect to.
  hosts: ["elastic-1.jdnet.lan:9200","elastic-2.jdnet.lan:9201","elastic-3.jdnet.lan:9202"]
  ssl.certificate_authorities: ["/etc/pki/jlastic/ca/ca.crt"]

  # Protocol - either `http` (default) or `https`.
  protocol: "https"

  # Authentication credentials - either API key or username/password.
  #api_key: "id:api_key"
  username: "elastic"
  password: "WYAtO5wlpqcD937UySyX"
```

Why the different port numbers?  Because, from what I could find all ports from containers in the swarm are available on each node in the swarm.  Exposing each Elasticsearch node as 9200 will cause the `docker stack deploy` command to fail.  All of the containers would request to use the 9200 port.

Why the different host names, could I just point them all to elastic-1.jdnet.lan?  The certificates are generated with the hostname and IP address of each host.  Connecting to elastic-1.jdnet.lan:9201 will redirect you on the swarm network to the es02 container and therefore the cert would be valid for es02, elastic-2.jdnet.lan, elastic-2 but not elastic-1.jdnet.lan.


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


## Generating the Kibana password and elastic user login.

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
