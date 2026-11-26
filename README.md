# pymongo-api

Итоговый стенд — `sharding-repl-cache`: два шарда по три реплики, replica set config-серверов и Redis. Промежуточные стенды лежат в `mongo-sharding` и `mongo-sharding-repl`.

## Как запустить

Из корня репозитория:

```shell
cd sharding-repl-cache
docker compose up -d
bash scripts/init.sh
```

Стенду нужно около 8 ГБ RAM. Девять процессов mongod запускаются с `--wiredTigerCacheSizeGB 0.25`: это минимум, который принимает MongoDB 7, и вместе с mongos, Redis и приложением они не помещаются в 4 ГБ. Ниже 0.25 кэш поставить нельзя, процесс не стартует.

Повторный запуск `scripts/init.sh` ничего не пересоздаёт: replica set, шарды и тысяча документов уже на месте.

## Как проверить

Приложение: http://localhost:8080

В JSON поле `documents_count` не меньше 1000, у каждого шарда в `shards` три хоста, `cache_enabled` равен true.

Список пользователей: http://localhost:8080/helloDoc/users

Первый вызов читает базу и занимает около секунды. Второй и следующие берутся из Redis и должны уложиться в 100 мс.

Если проект запущен на виртуальной машине, белый адрес:

```shell
curl --silent http://ifconfig.me
```

Тогда приложение открывается как http://<ip виртуальной машины>:8080, swagger — http://<ip виртуальной машины>:8080/docs.
