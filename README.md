# Черновик инструкции

## Подготовка и запуск

```bash
sudo apt update
sudo apt upgrade

sudo apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
sudo apt update
apt-cache policy docker-ce
sudo apt install docker-ce
sudo systemctl status docker
sudo usermod -aG docker ${USER}

sudo curl -L https://github.com/docker/compose/releases/download/v2.28.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

```bash
apt-get install fail2ban
nano /etc/fail2ban/jail.local
```
```
[sshd]
## если в течении 1 часа:
findtime    = 3600
## произведено 6 неудачных попыток логина:
maxretry    = 6
## то банить IP на 24 часа:
bantime     = 86400
```

# --------------- Подкачка
```bash
# Проверить есть ли уже swap
free -h

sudo fallocate -l 3G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl vm.swappiness=10

# Проверить результат
free -h
```

# --------------- Сертификат
```bash
sudo apt update
sudo apt install snapd

sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot certonly --standalone -d {{ FULL_DOMAIN }}
```

```bash
mkdir -p synapse postgres element turn
```

- генерация конфига SYNAPSE
```shell
docker run -it --rm -v "${PWD}/synapse:/data" -e SYNAPSE_SERVER_NAME=localhost -e SYNAPSE_REPORT_STATS=no matrixdotorg/synapse:latest generate
```

Генерация TURN_RANDOM_SECRET
```bash
openssl rand -hex 32
```

# TODO Создать и заполнить файлы в соответствии с env.example

```bash
cp env.example .env
cp synapse.homeserver.yaml.example synapse/homeserver.yaml
cp element.config.json.example element/config.json
cp turnserver.conf.example turn/turnserver.conf
cp nginx/nginx.conf.template.example nginx/nginx.conf.template 
```

```bash
docker-compose up -d
```

Создать админа:
```
docker exec -it matrix_synapse register_new_matrix_user -c /data/homeserver.yaml
```

## Что сделать

- Скрипт запуска
- Бэкапы
