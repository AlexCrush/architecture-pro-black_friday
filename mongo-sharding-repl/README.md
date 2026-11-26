# mongo-sharding-repl

Два шарда, у каждого replica set из трёх узлов. У configSrv тоже три узла: без этого падение одного config-сервера останавливает кластер. Приложение по-прежнему ходит только в mongos.

## Запуск

Из этой директории:

```shell
docker compose up -d
bash scripts/init.sh
```

Скрипт делает следующее:

1. Собирает replica set `configSrv` из `configSrv-1`, `configSrv-2`, `configSrv-3`.
2. Собирает replica set `shard1` из `shard1-1`, `shard1-2`, `shard1-3`.
3. Собирает replica set `shard2` из `shard2-1`, `shard2-2`, `shard2-3`.
4. Через mongos добавляет оба шарда целиком, включает шардирование `somedb.helloDoc` по хешу `name` и вставляет 1000 документов.

Запись идёт в текущий primary: роль выбирается выборами и может переехать на другой узел. Secondary получают те же документы репликацией.

Стенду нужно около 8 ГБ RAM. Девять mongod с кэшем WiredTiger 0.25 ГБ (меньше MongoDB 7 не принимает) вместе с mongos и приложением не влезают в 4 ГБ.

## Проверка

Приложение: http://localhost:8080

В JSON не меньше 1000 документов. В `shards` у каждого шарда три хоста — это и есть реплики.

Число реплик. `rs.status()` можно спросить у любого члена набора, не только у primary:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
```

Документы по шардам считает mongos. `countDocuments()` на конкретном контейнере отвечает только если этот узел сейчас primary.

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
use somedb
db.helloDoc.aggregate([{ $collStats: { count: {} } }]).forEach(d => print(d.shard, d.count))
EOF
```
