```
dcu
dce -T mysql mysql -uroot -proot <<< 'create database pim_1'
dce -T mysql mysql -uroot -proot pim_1 < sql/mysql.sql

psql -h 0 -U postgres -c "select set_config('app.tenant', 'tenant#1', false)" -c 'select setseed(0.1)' -a -f src/schema.sql -f fixtures.sql

curl --request POST --url 0:8083/connectors --header 'Content-Type: application/json' --data @- << EOF
{
  "name": "$pim_name-source",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    "database.hostname": "mysql",
    "database.port": "3306",
    "database.user": "root",
    "database.password": "root",
    "database.server.id": "100001",
    "database.server.name": "$pim_name",
    "database.include.list": "$pim_name",
    "database.history.kafka.bootstrap.servers": "redpanda:9092",
    "database.history.kafka.topic": "schema-changes.$pim_name",
    "database.allowPublicKeyRetrieval": true,
    "transforms": "Reroute",
    "transforms.Reroute.type": "io.debezium.transforms.ByLogicalTableRouter",
    "transforms.Reroute.topic.regex": "^$pim_name\\\.$pim_name\\\.(.*)$",
    "transforms.Reroute.topic.replacement": "all_pims",
    "transforms.Reroute.key.field.name": "tenant",
    "transforms.Reroute.key.field.regex": ".*",
    "transforms.Reroute.key.field.replacement": "$pim_name"
  }
}
EOF
```

```
curl --request POST --url 0:8083/connectors --header 'Content-Type: application/json' --data @- << EOF
{
    "name": "postgres-sink",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "all_pims",
        "connection.url": "jdbc:postgresql://postgres:5432/pim?user=postgres&password=postgres",
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false",
        "auto.create": "true",
        "insert.mode": "upsert",
        "delete.enabled": "true",
        "pk.fields": "id,tenant",
        "pk.mode": "record_key"
    }
}
EOF
```
