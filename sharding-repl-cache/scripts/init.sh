#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

wait_ping() {
  local service=$1
  local port=$2
  for _ in $(seq 1 40); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 1)'; then
      return 0
    fi
    sleep 2
  done
  echo "нет ответа от $service" >&2
  exit 1
}

wait_primary() {
  local service=$1
  local port=$2
  for _ in $(seq 1 40); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet --eval 'quit(rs.status().members.some(m => m.stateStr == "PRIMARY") ? 0 : 1)'; then
      return 0
    fi
    sleep 2
  done
  echo "нет primary у $service" >&2
  exit 1
}

for service in configSrv-1 configSrv-2 configSrv-3; do
  wait_ping "$service" 27019
done
for service in shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3; do
  wait_ping "$service" 27018
done

echo "configSrv"
docker compose exec -T configSrv-1 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "configSrv",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv-1:27019" },
    { _id: 1, host: "configSrv-2:27019" },
    { _id: 2, host: "configSrv-3:27019" }
  ]
})
EOF
wait_primary configSrv-1 27019

echo "shard1"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF
wait_primary shard1-1 27018

echo "shard2"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF
wait_primary shard2-1 27018

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
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF

echo "реплик shard1:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
echo "реплик shard2:"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
echo "документов по шардам:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
use somedb
db.helloDoc.aggregate([{ $collStats: { count: {} } }]).forEach(d => print(d.shard, d.count))
EOF
