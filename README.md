# tgrun 1.1.0

`tgrun` запускает команду, показывает её обычный вывод в терминале, сохраняет код
завершения и отправляет итог в Telegram. Статический бинарник не требует Go или
`curl` на целевом сервере.

```bash
tgrun rsync -aHAX /data/ /backup/data/
```

В Telegram придут сервер, пользователь, команда, код возврата, время запуска и
продолжительность. При ошибке по умолчанию добавляются последние строки вывода.
`tgrun` возвращает тот же код завершения, что и запущенная команда.

## Настройка

Основной конфиг — `/etc/tgrun.conf`:

```ini
bot_token=1234567890:AAxxxxxxxxxxxxxxxxxxxxxxxx
chat_id=-1001234567890
thread_id=
send_output=on-error
output_lines=20
http_timeout_seconds=15
```

Защитите токен:

```bash
sudo chown root:root /etc/tgrun.conf
sudo chmod 600 /etc/tgrun.conf
```

Если `tgrun` запускается не от root, этому пользователю потребуется право читать
конфиг. Можно указать отдельный файл:

```bash
tgrun --config "$HOME/.config/tgrun.conf" test
```

Значения `TG_BOT_TOKEN` и `TG_CHAT_ID` из окружения переопределяют конфиг.

### Как узнать chat_id

Заполните только `bot_token`, отправьте боту сообщение и выполните:

```bash
sudo tgrun get-chat-id
```

Команда покажет найденные `chat_id` и, для форумной темы, `thread_id`. Если
список пуст, отправьте боту новое сообщение. В группе может понадобиться
упомянуть бота или отключить privacy mode через BotFather.

Проверка отправки:

```bash
sudo tgrun test
tgrun notify "Резервное копирование запущено"
```

## Главное правило: когда нужен bash -lc

`tgrun` запускает программу напрямую, без промежуточной shell. Это безопасно и
правильно для обычных команд:

```bash
tgrun sleep 10
tgrun rsync -aHAX --numeric-ids /data/ /backup/data/
```

Но пайп `|`, перенаправления `>`, `>>`, `2>&1`, подстановка `$(...)`, переменные,
условия, циклы и многострочный shell-код понимает не `tgrun`, а Bash. Поэтому
такой код нужно передавать Bash одним аргументом:

```bash
tgrun bash -lc 'mysqldump --single-transaction mydb | gzip > /backup/mydb.sql.gz'
```

Одинарные кавычки вокруг скрипта важны: они не дают текущей shell заранее
раскрыть `$VAR` и `$(command)`. Раскрытие произойдёт внутри `bash -lc`.

Неправильно:

```bash
tgrun 'mysqldump mydb | gzip > /backup/mydb.sql.gz'
```

Здесь весь текст станет именем исполняемого файла, и команда завершится с кодом
`127`.

### mysqldump и gzip

```bash
tgrun bash -lc '
set -o pipefail
mysqldump --single-transaction --routines --events mydb \
  | gzip > /backup/mydb-$(date +%F).sql.gz
'
```

`set -o pipefail` заставляет pipeline завершиться ошибкой, если упал
`mysqldump`, даже когда `gzip` успел завершиться успешно.

### XtraBackup, pigz и xbstream

```bash
tgrun bash -lc '
set -o pipefail

BACKUP_FILE=$(ls -1t /data/backups/maindb-*.xb.gz 2>/dev/null | head -1)
if [[ -z "$BACKUP_FILE" ]]; then
    echo "Архив резервной копии не найден" >&2
    exit 1
fi

echo "Распаковывается: $BACKUP_FILE"
pigz -dc "$BACKUP_FILE" \
  | docker run --rm -i \
      --name xb-unpack-maindb \
      --log-driver=none \
      -v /data/mysql:/backup \
      percona/percona-xtrabackup:2.4.24 \
      xbstream -x -C /backup

rc=("${PIPESTATUS[@]}")
echo "pigz=${rc[0]} xbstream=${rc[1]}"
(( rc[0] == 0 )) || exit "${rc[0]}"
(( rc[1] == 0 )) || exit "${rc[1]}"
'
```

### Длинный сценарий из файла

Для повторяемых или длинных операций удобнее отдельный исполняемый файл:

```bash
sudo install -m 0700 unpack-maindb.sh /root/unpack-maindb.sh
sudo tgrun /root/unpack-maindb.sh
```

В самом файле укажите shebang и `pipefail`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# Команды резервного копирования или восстановления
```

## Установка

### Debian/Ubuntu через .deb

Выберите пакет своей архитектуры:

```bash
sudo apt install ./tgrun_1.1.0_amd64.deb
# или
sudo apt install ./tgrun_1.1.0_arm64.deb
```

Пакет устанавливает:

- `/usr/bin/tgrun`;
- `/etc/tgrun.conf` с правами `0600`;
- документацию в `/usr/share/doc/tgrun`.

`/etc/tgrun.conf` объявлен conffile: при обновлении изменённый администратором
конфиг не заменяется без решения dpkg.

### Через install.sh

Опубликуйте файлы релиза в одном HTTPS-каталоге:

```bash
curl -fsSL https://tools.example.com/tgrun/install.sh \
  | sudo TGRUN_BASE_URL=https://tools.example.com/tgrun sh
```

Установщик определит `amd64` или `arm64`, сверит SHA256, установит бинарник в
`/usr/local/bin/tgrun` и создаст `/etc/tgrun.conf`, только если его ещё нет.

### Вручную

Для amd64:

```bash
curl -fLO https://tools.example.com/tgrun/tgrun-linux-amd64
curl -fLO https://tools.example.com/tgrun/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
sudo install -m 0755 tgrun-linux-amd64 /usr/local/bin/tgrun
sudo install -m 0600 tgrun.conf.example /etc/tgrun.conf
```

Для ARM64 замените имя бинарника на `tgrun-linux-arm64`.

## Обновление

Через Debian-репозиторий:

```bash
sudo apt update
sudo apt install tgrun
```

Локальным новым пакетом:

```bash
sudo apt install ./tgrun_1.1.0_amd64.deb
```

Через HTTP-установщик повторите команду установки. Существующий
`/etc/tgrun.conf` сохранится. Перед загрузкой можно проверить опубликованные
файлы:

```bash
curl -fLO https://tools.example.com/tgrun/SHA256SUMS
sha256sum -c SHA256SUMS
```

## Cron

В cron используйте абсолютные пути и укажите конфиг, доступный пользователю:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 2 * * * /usr/bin/tgrun /usr/local/sbin/backup-db.sh >>/var/log/backup-db.log 2>&1
```

Если shell-логика находится прямо в crontab:

```cron
30 2 * * * /usr/bin/tgrun /bin/bash -lc 'set -o pipefail; mysqldump mydb | gzip > /backup/mydb-$(date +\%F).sql.gz'
```

В crontab символ `%` нужно экранировать как `\%`. Практичнее вынести сложную
команду в файл.

## systemd

Пример `/etc/systemd/system/backup-db.service`:

```ini
[Unit]
Description=Database backup with Telegram notification

[Service]
Type=oneshot
ExecStart=/usr/bin/tgrun /usr/local/sbin/backup-db.sh
```

Для pipeline:

```ini
ExecStart=/usr/bin/tgrun /bin/bash -lc 'set -o pipefail; mysqldump mydb | gzip > /backup/mydb.sql.gz'
```

В `ExecStart=` нет обычной shell: `|` и `>` также требуют явного
`/bin/bash -lc`. После создания или изменения unit:

```bash
sudo systemctl daemon-reload
sudo systemctl start backup-db.service
sudo systemctl status backup-db.service
```

## Команды

```text
tgrun [--config FILE] COMMAND [ARG...]
tgrun [--config FILE] run COMMAND [ARG...]
tgrun [--config FILE] notify TEXT
tgrun [--config FILE] test
tgrun [--config FILE] get-chat-id
tgrun version
```

`run` необязателен: `tgrun run rsync ...` и `tgrun rsync ...` равнозначны.

Параметр `send_output` принимает `always`, `on-error` или `never`.

## Сборка и выпуск

Нужны Go 1.22+, `sha256sum`, `tar` и `dpkg-deb`:

```bash
gofmt -w ./*.go
go test ./...
go vet ./...
./release.sh
```

`release.sh` собирает статические бинарники linux/amd64 и linux/arm64, два
Debian-пакета, контрольные суммы, архив исходников и release bundle.

## Изменения 1.1.0

- подробные примеры `bash -lc`, pipeline, XtraBackup, cron и systemd;
- установка и обновление вручную, через `install.sh` и `.deb`;
- Debian-пакеты для amd64 и arm64 с защищённым conffile;
- воспроизводимые build/release scripts и базовые Go-тесты;
- `get-chat-id` из версии 1.0.1 включён в релиз.
