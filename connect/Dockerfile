FROM confluentinc/cp-kafka-connect:7.7.1

# Versions pinned after first successful run
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:3.2.6 \
 && confluent-hub install --no-prompt confluentinc/kafka-connect-s3:12.1.13