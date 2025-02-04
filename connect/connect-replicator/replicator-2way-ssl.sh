#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.yml"


log "########"
log "##  SSL authentication"
log "########"

log "Sending messages to topic test-topic-ssl"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic-ssl --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "Creating Confluent Replicator connector with SSL authentication"
playground connector create-or-update --connector duplicate-topic-ssl << EOF
{
                    "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
                    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "src.consumer.group.id": "duplicate-topic",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.ssl.keystore.type" : "JKS",
                    "confluent.topic.ssl.truststore.type" : "JKS",
                    "confluent.topic.security.protocol" : "SSL",
                    "provenance.header.enable": true,
                    "topic.whitelist": "test-topic-ssl",
                    "topic.rename.format": "test-topic-ssl-duplicate",
                    "dest.kafka.bootstrap.servers": "broker:9092",
                    "dest.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "dest.kafka.ssl.keystore.password" : "confluent",
                    "dest.kafka.ssl.key.password" : "confluent",
                    "dest.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "dest.kafka.ssl.truststore.password" : "confluent",
                    "dest.kafka.security.protocol" : "SSL",
                    "src.kafka.bootstrap.servers": "broker:9092",
                    "src.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "src.kafka.ssl.keystore.password" : "confluent",
                    "src.kafka.ssl.key.password" : "confluent",
                    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "src.kafka.ssl.truststore.password" : "confluent",
                    "src.kafka.security.protocol" : "SSL"
          }
EOF



sleep 10

log "Verify we have received the data in test-topic-ssl-duplicate topic"
playground topic consume --topic test-topic-ssl-duplicate --min-expected-messages 10 --timeout 60
