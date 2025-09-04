migration_mode=${args[--migration-mode]}

discovery_output_dir="$root_folder/connect-migration-utility-discovery-output"
if [ ! -d "$discovery_output_dir" ]
then
	logerror "❌ $discovery_output_dir does not exist, please run playground connect-migration-utility discovery first !"
	exit 1
fi

log "🪄 Migrate discovered local connectors in $discovery_output_dir as fully managed connectors"

get_environment_used
if [ "$migration_mode" == "stop_create_latest_offset" ] ||  [ "$migration_mode" == "create_latest_offset" ]
then
	if [ "$environment" != "ccloud" ]
	then
		logerror "❌ --migration-mode $migration_mode is only supported with --environment ccloud"
		exit 1
	fi
fi

log "🔌 boostrapping ccloud environment"
bootstrap_ccloud_environment "" "" "true"

get_ccloud_connect

docker run -i --rm --network=host -v "$discovery_output_dir:/discovery_output_dir" vdesabou/docker-connect-migration-utility:latest bash -c "cd connect-migration-utility && python src/migrate_connector_script.py --worker-urls 'http://localhost:8083' --disable-ssl-verify --environment-id $environment --cluster-id $cluster --bearer-token $CLOUD_API_KEY:$CLOUD_API_SECRET --kafka-auth-mode KAFKA_API_KEY --kafka-api-key $CLOUD_KEY --kafka-api-secret $CLOUD_SECRET --fm-config-dir /discovery_output_dir/discovered_configs/successful_configs/fm_configs --migration-mode $migration_mode" > /tmp/output.log 2>&1
ret=$?
if [ $ret -ne 0 ]
then
	logerror "❌ Failed to Migrate Kafka Connectors, check output below"
	cat /tmp/output.log
	exit 1
else
	set +e
	grep "ERROR" /tmp/output.log > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		logerror "❌ Found ERROR in the output of the migration process, please check output below"
		grep "ERROR" /tmp/output.log
		exit 1
	fi
	set -e
	log "✅ Migrate Kafka Connectors was successful!"
	playground switch-ccloud

	playground connector status

	log "Do you want to see the connector in your browser ?"
	check_if_continue
	playground connector open-ccloud-connector-in-browser
fi