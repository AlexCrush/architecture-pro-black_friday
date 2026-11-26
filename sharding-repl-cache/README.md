# sharding-repl-cache

Два шарда по три реплики и Redis. Повторный запрос списка пользователей читает кеш и в MongoDB не идёт. Промах и запись по-прежнему идут в mongos.

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

Запись идёт в primary. Secondary получают те же документы репликацией.

## Проверка

Приложение: http://localhost:8080

В JSON не меньше 1000 документов, `cache_enabled` равен true. В `shards` у каждого шарда три хоста.

Список пользователей: http://localhost:8080/helloDoc/users

Первый вызов читает базу и занимает около секунды. Второй и следующие берутся из Redis и должны уложиться в 100 мс.

Число реплик:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
```

Документы по шардам, через mongos:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
use somedb
db.helloDoc.aggregate([{ $collStats: { count: {} } }]).forEach(d => print(d.shard, d.count))
EOF
```
