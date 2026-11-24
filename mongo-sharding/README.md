# mongo-sharding

Два шарда. Приложение ходит только в mongos. У шарда и у configSrv по одному узлу: MongoDB не принимает шард вне replica set, дополнительные реплики будут в следующем задании.

## Запуск

Из этой директории:

```shell
docker compose up -d
bash scripts/init.sh
```

Скрипт делает следующее:

1. Поднимает replica set `configSrv` из одного узла.
2. Поднимает replica set `shard1` и `shard2`, тоже по одному узлу.
3. Через mongos добавляет оба шарда, включает шардирование базы `somedb` и коллекции `helloDoc` по хешу поля `name`.
4. Вставляет 1000 документов. Хеш режет коллекцию сразу, поэтому документы не остаются на одном шарде.

## Проверка

Приложение: http://localhost:8080

В JSON поле `mongo_is_mongos` равно true, в `collections.helloDoc.documents_count` не меньше 1000, в `shards` два шарда.

Количество документов на каждом шарде:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма двух чисел равна общему количеству в приложении.
