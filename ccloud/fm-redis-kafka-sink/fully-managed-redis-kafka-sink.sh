#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic redis_users
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull
 
log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done


log "Sending messages to topic redis_users"
playground topic produce -t redis_users --nb-messages 3 --forced-value '{"f1":"value%g"}' --key "key1" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF


connector_name="RedisKafkaSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
	"connector.class": "RedisKafkaSink",
	"name": "$connector_name",
	"kafka.auth.mode": "KAFKA_API_KEY",
	"kafka.api.key": "$CLOUD_KEY",
	"kafka.api.secret": "$CLOUD_SECRET",
	"input.data.format" : "AVRO",
	"input.key.format" : "STRING",
	"redis.host": "$NGROK_HOSTNAME",
	"redis.port": "$NGROK_PORT",
	"redis.server.mode": "Standalone",
	"topics": "redis_users",
	"tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify data is in Redis"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.users.0" "{\"topic\":\"users\",\"partition\":0,\"offset\":2}" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "__kafka.offset.users.0" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name