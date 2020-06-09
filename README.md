This will deploy a cluster of three elastic nodes and a kibana to a set of system in a docker swarm configuration.

Each container is pinned to a different system.

Instructions:

- Setup a docker swarm of 4 systems.

- Define one of the nodes as the master

- Ensure the master has root ssh key access to all other nodes in swarm

- This has only been tested with each swarm node being hostname resolvable.
- Set variables in the .env file
- rc.sh will print out each step that is taken to deploy, so you can test each step separately at first.
- Or, run './rc.sh scratch' to deploy


# Notes that are left for reference

stack name is prepended to the volumes.

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
`
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
`

Replace the 'kib01' service's 'ELASTIC_PASSWORD' value to the 'PASSWORD kibana' Field In the docker compose template "elastic-docker-tls.yml", that file was generated during setup.

Use user:elastic, password:'<PASSWORD elastic from above>' When loging into the kibana interface.

Instructions from https://www.elastic.co/guide/en/elastic-stack-get-started/current/get-started-docker.html#:~:text=elastic%2Ddocker%2Dtls.,distributed%20deployment%20with%20multiple%20hosts.

docker exec `docker ps | grep es01| awk '{ print $1 }'` /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://es01:9200"
docker stack deploy -c elastic-docker-tls.yml jlastic
