#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

wait_primary() {
  local service=$1
  local port=$2
  for _ in $(seq 1 40); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)'; then
      return 0
    fi
    sleep 2
  done
  echo "нет primary у $service" >&2
  exit 1
}

echo "configSrv"
docker compose exec -T configSrv mongosh --port 27019 --quiet <<'EOF'
try { rs.status() } catch (e) {
  rs.initiate({
    _id: "configSrv",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27019" }]
  })
}
EOF
wait_primary configSrv 27019

echo "shard1"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
try { rs.status() } catch (e) {
  rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
  })
}
EOF
wait_primary shard1 27018

echo "shard2"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<'EOF'
try { rs.status() } catch (e) {
  rs.initiate({
    _id: "shard2",
    members: [{ _id: 0, host: "shard2:27018" }]
  })
}
EOF
wait_primary shard2 27018

echo "mongos"
ready=0
for _ in $(seq 1 40); do
  if docker compose exec -T mongos mongosh --port 27017 --quiet --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 1)'; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "mongos не ответил" >&2
  exit 1
fi

docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
const shards = db.adminCommand({ listShards: 1 }).shards.map(s => s._id)
if (!shards.includes("shard1")) sh.addShard("shard1/shard1:27018")
if (!shards.includes("shard2")) sh.addShard("shard2/shard2:27018")
const hello = db.getSiblingDB("config").collections.findOne({ _id: "somedb.helloDoc" })
if (!hello) {
  sh.enableSharding("somedb")
  sh.shardCollection("somedb.helloDoc", { name: "hashed" })
}
const docs = db.getSiblingDB("somedb")
if (docs.helloDoc.countDocuments() === 0) {
  for (var i = 0; i < 1000; i++) docs.helloDoc.insertOne({ age: i, name: "ly" + i })
}
EOF

echo "shard1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF

echo "shard2:"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
