## Дисклеймер

Тестировалось на VPS с Debian 12 и Ubuntu 24.04. В скрипте стоит проверка ОС, на любых других дистрибутивах, кроме Ubuntu и Debian, установщик работать не будет! Крайне рекомендуется иметь как минимум 2 гигабайта RAM. Текстовые сообщения, аудио- и видеозвонки работают корректно, проверялось как на веб-версии, так и на мобильных устройствах (Android, iOS). Для корректной работы настоятельно рекомендуется использовать арендованный VPS, находящийся за пределами РФ.

## Установка

Если после клонирования репозитория скрипты не являются исполняемыми, то необходимо выполнить команду `chmod +x`.

Запуск установки выполняется через `./install.sh`, данный скрипт обновит системные пакеты, добавит swap, установит Docker (если уже установлен на системе - можно данный шаг пропустить), установит TLS-сертификат от Let's Encrypt, создаст необходимые для конфигурационных файлов директории. После чего начнётся этап интерактивной установки, где Вы сможете задать креды для Postgres, PGAdmin, Grafana, Prometheus, сгенерировать секрет для TURN. В квадратных скобках написаны дефолтные значения, если нажать Enter, то применится дефолтное значение для переменной в файле .env.

ВАЖНО: если вдруг после завершения скрипта пользователь не будет добавлен в группу docker, то необходимо выйти из SSH-сессии и переподключиться к серверу, после чего проверить наличие пользователя в группе.

## Файлы конфигурации

Все необходимые конфиги создатутся автоматически, файл .env будет заполнен в соответствии с Вашими данными, которые Вы указали в процессе установки. Заполнить нужно будет только переменную `PUBLIC_IP_ADDR=` в `.env` (внешний IP-адрес сервера), а также переменные `relay-ip=` и `external-ip=` в файле `turn/turnserver.conf`.

## Basic Auth

Т.к. для дашборда Traefik, Grafana, Prometheus и PGAdmin используется Basic Auth, то сперва нужно сгенерировать креды. Сделать это можно следующей командой:

```bash
htpasswd -nb USERNAME PASSWORD
```

Полученный результат необходимо вставить в файл `traefik/dynamic/auth.yml`.

Пример заполненного файла `traefik/dynamic/auth.yml` (для кредов username:password):

```http:
  middlewares:
    basic-auth:
      basicAuth:
        users:
          - "username:$apr1$8XebVOSJ$p3q4OyAscRg4hKiIqyTaN0"
```

Остальные пользователи добавляются следующей строкой. Все изменения, вносящиеся в файлы `traefik/dynamic/auth.yml`, `traefik/dynamic/dashboard.yml` и `traefik/dynamic/matrix-wellknown.yml`, не требуют перезапуска контейнера `traefik` и подхватываются им автоматически.

## Запуск

```bash
docker compose up -d
```

## Создание учётных записей

Учётные записи пользователей создаются следующей командой:

```
docker exec -it matrix_synapse register_new_matrix_user -c /data/homeserver.yaml
```
Первая учётная запись должна иметь админские права, остальные - по желанию.

В дальнейшем все учётные записи для пользователей будут также создаваться через эту команду.

## Резервное копирование

Скрипты резервного копирования лежат в директории `/backup`. Там же находится файл конфигурации `env.tpl`, который Вы можете редактировать в зависимости от Ваших нужд (к примеру, указать другую директорию хранения бэкапов или срок их хранения на сервере). Скрипт `install.sh` создаст директории, где будут храниться бэкапы, после чего произведёт установку systemd-юнита, который будет снимать бэкапы раз в сутки (стандартное время - 03:00). Скрипт `backup.sh` произведёт процедуру снятия резервной копии контейнеров Postgres, Synapse и Element, после чего поместит архивы в соответствующие контейнерам директории, также он проверяет наличие резервных копий, и если они не соответствуют параметру, указанному в переменной `RETENTION_DAYS=`, то удаляет их. Скрипт `restore.sh` отвечает за процесс восстановления из резервной копии и выведет все доступные бэкапы на экран, после чего необходимо будет ввести таймштамп бэкапа, из которого Вы хотите восстановиться. Если же просто нажать Enter, то будет выбран бэкап, снятый последним.

## Планы на будущее
Написать плейбук для Ansible.

## Disclaimer

Tested on VPS with Debian 12 and Ubuntu 24.04.
The script includes an OS check — the installer will not work on any distributions other than Ubuntu and Debian.
It is strongly recommended to have at least 2 GB of RAM.

Text messages, audio calls, and video calls work correctly. Testing was performed both on the web version and on mobile devices (Android, iOS).

For proper operation, it is highly recommended to use a rented VPS located outside the Russian Federation.

## Installation

If after cloning the repository the scripts are not executable, you need to run the `chmod +x` command.

The installation is started via `./install.sh`.
This script will:

Update system packages

Add swap

Install Docker (if Docker is already installed on the system, this step can be skipped)

Install a TLS certificate from Let’s Encrypt

Create the required directories for configuration files

After that, the interactive installation stage will begin, where you can set credentials for:

Postgres

PGAdmin

Grafana

Prometheus

You will also be able to generate a secret for TURN.

Default values are shown in square brackets. If you press Enter, the default value will be applied to the corresponding variable in the .env file.

WARNING:
If after the script finishes the user is not added to the docker group, you must log out of the SSH session and reconnect to the server, then verify that the user is a member of the group.

## Configuration files

All required configuration files will be created automatically.
The .env file will be populated according to the data you provided during installation.

You will only need to manually fill in:

`PUBLIC_IP_ADDR=` in the `.env` file (the server’s external IP address)

`relay-ip=` and `external-ip=` variables in the `turn/turnserver.conf` file

## Basic Auth

Since Traefik Dashboard, Grafana, Prometheus, and PGAdmin are protected using HTTP Basic Auth, credentials must be generated before accessing these services. Credentials can be generated using the following command:

`htpasswd -nb USERNAME PASSWORD`

The output of this command must be added to the file `traefik/dynamic/auth.yml`

Example auth.yml configuration (username:password):

```http:
  middlewares:
    basic-auth:
      basicAuth:
        users:
          - "username:$apr1$8XebVOSJ$p3q4OyAscRg4hKiIqyTaN0"
```

Additional users can be added by appending new entries to the users list.

Any changes made to the files `traefik/dynamic/auth.yml`, `traefik/dynamic/dashboard.yml` and `traefik/dynamic/matrix-wellknown.yml` do not require restarting the traefik container. Traefik automatically detects and applies changes to dynamic configuration files at runtime.

## Startup

```bash
docker compose up -d
```

## Creating user uccounts

User accounts are created using the following command:

```bash
docker exec -it matrix_synapse register_new_matrix_user -c /data/homeserver.yaml
```

The first account must have admin privileges; the rest are optional.

All subsequent user accounts should also be created using this command.

## Backups

Backup scripts are located in the `/backup` directory.
The `env.tpl` configuration file is also located there — you can edit it according to your needs (for example, specify a different backup storage directory or change the retention period).

The `install.sh` script will create directories for storing backups and install a systemd unit that performs backups once per day (default time: 03:00).

The backup.sh script performs the backup procedure for the Postgres, Synapse, and Element containers, then places the archives into the corresponding container directories. It also checks existing backups and removes those that exceed the value specified in the `RETENTION_DAYS=` variable.

The `restore.sh` script handles the restore process. It will display all available backups, after which you need to enter the timestamp of the backup you want to restore from.
If you simply press Enter, the most recent backup will be selected.

## Future Plans
Write an Ansible playbook.
