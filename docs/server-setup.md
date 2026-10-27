# Конфигурация виртуальной машины devops-vm

Практическая работа №5. Осадчев Никита, ЭФБО-04-24.
Система: Ubuntu Server 24.04.5 LTS после обновления, без графического рабочего стола; исходный ISO — 24.04.4.
Пароли и закрытые ключи в репозитории не хранятся.

## 1. Параметры машины

- VirtualBox 7.2.20, тип Ubuntu 24.04 (64-bit).
- Память: 2048 МБ; процессоры: 2.
- Диск: 25 ГБ, динамический VDI.
- Исходный ISO: ubuntu-24.04.4-live-server-amd64.iso.
- SHA256: e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433.
- Источник контрольной суммы: https://releases.ubuntu.com/24.04/SHA256SUMS.
- Установка автоматизирована через штатный VirtualBox unattended/autoinstall; использован обычный Ubuntu Server, не minimized.

## 2. Сетевые интерфейсы

| Интерфейс | Тип | IPv4 | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15 | Интернет и обновления через NAT |
| enp0s8 | Host-only | 192.168.56.101 | Прямое соединение Windows с VM |

Адаптер Windows: VirtualBox Host-Only Ethernet Adapter, адрес 192.168.56.1/24.
Оба адреса VM получены по DHCP; перед следующей работой проверить `ip -brief address`.
Если Host-only адрес изменился, обновить Windows hosts.

## 3. Правило проброса портов

Правило NAT `ssh`: TCP, 127.0.0.1:2222 на Windows → порт 2222 гостя.
До усиления SSH гостевой порт был 22. После смены SSH-порта правило изменено.
Для работающей VM правило меняется так, из PowerShell:

```powershell
& 'C:/Program Files/Oracle/VirtualBox/VBoxManage.exe' controlvm devops-vm natpf1 delete ssh
& 'C:/Program Files/Oracle/VirtualBox/VBoxManage.exe' controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

## 4. Учётные записи

- `student`: первоначальная учётная запись установки, состоит в sudo; консольное восстановление.
- `devops`: отдельная рабочая учётная запись, состоит в sudo; SSH-аутентификация только по ключу ed25519.
- Права `/home/devops/.ssh`: 700; `authorized_keys`: 600; владелец devops.
- Пароли сгенерированы и сохранены только на Windows вне Git. Sudo использует пароль учётной записи.
- Отдельный закрытый ключ Windows: `~/.ssh/devops_vm`; публичный: `~/.ssh/devops_vm.pub`.
- Ключ доступа к GitHub не используется для сервера.

Конфигурация клиента Windows (`~/.ssh/config`):

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Резервная копия исходного файла: `/etc/ssh/sshd_config.backup`.
Настройки: `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Включена служба ssh.service, ssh.socket отключён. Конфликтующие более ранние активные директивы PasswordAuthentication в drop-in файлах закомментированы. Основной sshd_config сохранён.
Проверять итоговые значения командой `sudo sshd -T`, фактический порт — `sudo ss -tlnp`.
При правках держать старую SSH-сессию открытой до успешного входа во второй.
Отпечаток ключа сервера проверен по выводу из виртуальной машины, независимо от SSH.

## 6. Правила межсетевого экрана

- UFW: active; deny incoming; allow outgoing.
- 2222/tcp: LIMIT (IPv4 и IPv6).
- 80/tcp и 443/tcp: ALLOW (IPv4 и IPv6).
- Логирование: medium. Закрытый порт для проверки: 8080/tcp.
- Проверка: `sudo ufw status verbose`; блокировки: `/var/log/ufw.log`, запись UFW BLOCK.
- `ufw allow ssh` не используется: имя ssh в /etc/services означает порт 22.

## 7. Снимки состояния

1. `01-clean-install`: Ubuntu установлена и обновлена; student, два интерфейса, SSH на 22.
2. `02-keys-configured`: создан devops, перенесён отдельный ключ, проверен вход без пароля.
3. `03-ssh-hardened`: запрет root/пароля, SSH на 2222, изменено правило NAT.

Снимки — точки возврата; актуальная рабочая VM дополнительно содержит UFW и настройку имени.

## Восстановление после 01-clean-install

Сначала проверить правило NAT: на исходном снимке гостевой SSH-порт 22, на Windows 2222.
Войти `ssh student@127.0.0.1 -p 2222`. Пароль взять из локального хранилища Windows.

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

Во втором терминале Windows передать существующий публичный ключ:

```powershell
Get-Content $env:USERPROFILE/.ssh/devops_vm.pub | ssh -p 2222 devops@127.0.0.1 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
ssh devops
```

Войти под devops, выполнить `sudo -v`. Записать приведённый выше блок SSH в `99-hardening.conf` через `sudo tee`, затем:

```bash
sudo cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo grep -Rns '^[[:space:]]*PasswordAuthentication' /etc/ssh/sshd_config.d/
# В более ранних drop-in файлах закомментировать PasswordAuthentication yes, если есть.
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
sudo systemctl disable --now ssh.socket
sudo systemctl enable ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

Изменить NAT на гостевой порт 2222 командами раздела 3 и проверить новую сессию `ssh devops`. Далее:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment HTTP
sudo ufw allow 443/tcp comment HTTPS
sudo ufw --force enable
sudo ufw logging medium
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

На Windows запись в `C:/Windows/System32/drivers/etc/hosts`:

```text
192.168.56.101 devops.local
```

Проверить `ssh devops.local`, запрет входа root и пароля, `sudo ufw status verbose`.
Файл `scripts/audit.sh` скопировать на VM и запустить: `sudo bash scripts/audit.sh`.
Ожидаются 6 успешных проверок и код 0. При временном MaxAuthTries 10 ожидается код 1; затем обязательно вернуть 3.

## Необязательный SSH-туннель

На VM: `python3 -m http.server 8080 --bind 127.0.0.1 --directory ~/restricted`.
На Windows: `ssh -L 127.0.0.1:9090:127.0.0.1:8080 -N devops`.
Ресурс доступен по http://127.0.0.1:9090; прямой доступ к 192.168.56.101:8080 блокируется.
Трафик проходит внутри разрешённого SSH-соединения на 2222; порт 8080 остаётся закрытым извне.

## Затруднение первого запуска

При первом запуске VirtualBox остановился на Loading essential drivers. Команды controlvm devops-vm pause и controlvm devops-vm resume позволили продолжить загрузку без сброса VM. При первом запуске cloud-init пересоздал host keys: окончательный отпечаток проверен по локальной консоли VM перед SSH, а не принят автоматически.

Живое сохранение оперативной памяти при создании 02-keys-configured зависло и было отменено через штатный IProgress.Cancel. После восстановления работы VM снимки создаются при выключенной гостевой системе, без сохранения RAM.

## 8. Веб-сервер

Практическая работа №6, 27.10.2026. Nginx 1.24.0 из Ubuntu noble-updates; пакеты `nginx`, `rsync`, `openssl`.
Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`, ссылка в `sites-enabled/devops-site`.
Её полная публичная копия: `config/nginx/devops-site.conf` в этом репозитории.
Стандартный `sites-enabled/default` отключён удалением ссылки; исходный файл сохранён.

Каталог `/var/www/devops-site` принадлежит `devops:devops`: каталоги 755, файлы 644.
Рабочие процессы `www-data` читают содержимое, но не изменяют его.
HTTP 80 перенаправляется кодом 301 на HTTPS 443, включая исходный URI.
Host-only даёт прямой доступ к стандартным портам без дополнительного проброса NAT.
Разрешены TLS 1.2 и 1.3. HSTS для учебного самоподписанного сертификата не включён.
Оба блока server пишут запросы в `/var/log/nginx/devops-site.access.log`, ошибки — в `devops-site.error.log`.

Сертификат `/etc/ssl/certs/devops.crt`: `root:root`, 644; закрытый ключ `/etc/ssl/private/devops.key`: `root:root`, 600.
SAN: `DNS:devops.local`, RSA 2048, срок 365 дней. Фактический выпуск: 27.10.2026 13:50:39 UTC;
окончание: 27.10.2027 13:50:39 UTC. Ключ не копируется за пределы VM и не публикуется.

Восстановление после настройки SSH/UFW из разделов 1–7, команды на VM:

```bash
sudo apt update && sudo apt install -y nginx rsync openssl
sudo install -d -m 755 -o devops -g devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

На Windows из корня репозитория передать публичную конфигурацию:

```powershell
scp config/nginx/devops-site.conf devops:devops-site.conf
```

На VM активировать ресурс:

```bash
sudo install -m 644 ~/devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
if test -L /etc/nginx/sites-enabled/default; then sudo unlink /etc/nginx/sites-enabled/default; fi
sudo nginx -t && sudo systemctl reload nginx
```

Перед повторным выпуском сохранить сертификат по проверенному SSH-каналу.
После повторного выпуска нужно заново передать клиенту новую открытую часть:

```bash
# WSL1, SSH host key уже сверён независимо от SSH
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --cacert ~/devops.crt -I https://devops.local
```

Клиент Windows для rsync: отдельная Ubuntu 24.04 WSL1 `DevOps-P6`, пользователь `nikita`.
Импортирован официальный rootfs Canonical с проверкой SHA256; существующая Ubuntu WSL2 сохранена.
Ключ и config скопированы в `/home/nikita/.ssh` с правами 600, каталог — 700.
В WSL `/etc/hosts` добавлено `192.168.56.101 devops.local`.
Для общей рабочей копии на `/mnt/c` задано `git config core.fileMode false`;
`core.autocrlf true` согласован с Windows, а `.gitattributes` закрепляет LF для `*.sh` и `site/*.html`.

После коммита запускать из корня репозитория или его подкаталога:

```bash
scripts/deploy.sh --dry-run
scripts/deploy.sh
```

Первый запуск с `--delete` обязательно проверяется через dry-run. Источник только `site/`,
назначение только `/var/www/devops-site/`. `--chmod=D755,F644` исправляет права 777 с Windows.
`--checksum` также восстанавливает вручную подменённое содержимое.
Один запуск использует ровно одно SSH-соединение rsync, BatchMode и проверенный known_hosts.
Проверка HTTPS использует `--cacert`, ограниченные таймауты и два повтора сетевого запроса.
Успех: код 0 и короткий хеш коммита; грязный Git, отсутствующий index, ошибка rsync/HTTPS: код 1.

Аудит на VM: `sudo bash ~/scripts/audit.sh` — 10 проверок, код 0.
Отрицательные опыты: `sudo env CERT_MIN_DAYS=400 bash ~/scripts/audit.sh` — код 1;
временный `chmod 666 /var/www/devops-site/index.html` — код 1. После опыта вернуть 644.

Снимок `04-nginx-https` создан при выключенной VM после HTTPS, до доставки `site/`.
Снимок `03b-practice5-complete` сохраняет полный итог №5 перед восстановлением `01-clean-install`.
Восстановление пользователя, SSH, UFW и имени повторено: аудит №5 дал 6/6, код 0.
Загрузка старого снимка потребовала вернуть профиль `Ubuntu24_LTS_64` и отключить ненужный звук;
из-за диагностики загрузки общий этап восстановления вышел за аудиторный лимит 10 минут.

## 9. Контейнеризация

Практическая работа №7, 27.10.2026. Установлены Docker Engine и CLI 29.9.2,
Compose v5.6.1, Buildx v0.38.1 и containerd 2.4.2 из официального APT-репозитория
Docker для Ubuntu 24.04 noble, amd64. Пакет Ubuntu `docker.io` не используется.
Установка: https://docs.docker.com/engine/install/ubuntu/.

После разделов 1–8 на VM выполнить:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

Группа `docker` содержит только `devops`, которому ранее выдано sudo. Доступ к
сокету Docker равнозначен возможностям root внутри VM; непривилегированные
учётные записи в эту группу не добавлять. Открыть новую SSH-сессию:

```bash
id
docker version
docker compose version
docker run --rm hello-world
```

Проект на сервере: `/home/devops/app`, владелец devops. Исходники находятся в
`app/` репозитория. Образ `devops-app:1.0` строится из `python:3.12-slim`.
Dockerfile копирует зависимости до кода, устанавливает точные версии из
requirements.txt, затем задаёт `USER app` и exec-форму CMD Gunicorn на 5000.
Файлы приложения в образе принадлежат root и имеют 644: app их читает, но не пишет.
Версии зависимостей сохранены по учебному шаблону; перед промышленным использованием
нужны отдельные обновление и проверка зависимостей.

Доставка с хоста, из корня репозитория в WSL1 DevOps-P6:

```bash
rsync -avz --delete --exclude=.env --chmod=D755,F644 --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/
```

Исключение `.env` обязательно и при повторной доставке: оно защищает серверный
файл от `--delete`. Нормализация прав устраняет исходные 777 на `/mnt/c`.
На VM создать секрет один раз; при существующем томе пароль не менять:

```bash
cd ~/app
umask 077
if test ! -e .env; then
  cp .env.example .env
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
fi
chmod 600 .env
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

Секрет `/home/devops/app/.env` принадлежит devops:devops, права 600, содержит
POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD и DB_HOST=db. Его нельзя копировать
на Windows, добавлять в Git, выводить в отчёт или помещать в образ.
Публичный `.env.example` содержит только `change_me`. `.gitignore` исключает `.env`,
`.dockerignore` исключает его из контекста сборки. Для проверки синтаксиса применять
`docker compose config --quiet`, поскольку обычный `config` раскрывает переменные.

Compose создаёт контейнеры `app-app-1` и `app-db-1`, сеть bridge `app_backend`
и именованный том `app_db_data`, смонтированный в PostgreSQL по пути
`/var/lib/postgresql/data`. Встроенный DNS сети разрешает имя `db` в адрес СУБД.
Приложение ждёт healthy от `pg_isready` с помощью `depends_on: service_healthy`.
`$$` в healthcheck откладывает раскрытие переменных до оболочки контейнера.
Тег `postgres:16-alpine` фиксирует основную версию PostgreSQL.

Приложение слушает 0.0.0.0:5000 внутри контейнера, но на VM опубликовано только
`127.0.0.1:5000:5000`. Порт 5432 не опубликован вообще. Nginx с хоста VM имеет
доступ к loopback; клиент Windows обращается только к HTTPS 443. Правила UFW из
№5 сохранены. Публикация Docker на 0.0.0.0 обходит UFW через NAT/FORWARD, поэтому
отсутствие allow 5000 в UFW не заменяет привязку к 127.0.0.1.

В HTTPS-блок `/etc/nginx/sites-available/devops-site` добавить:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Завершающий `/` в proxy_pass заменяет префикс `/app/`: `/app/health` передаётся
как `/health`. Статический `location /` и каталог `/var/www/devops-site` сохранены.
Полная конфигурация находится в `config/nginx/devops-site.conf`. Передать её
через scp, затем на VM:

```bash
sudo install -m 644 ~/devops-site.conf /etc/nginx/sites-available/devops-site
sudo nginx -t && sudo systemctl reload nginx
docker compose exec app id
docker compose exec app getent hosts db
sudo ss -tlnp | grep -E ':(5000|5432)\b'
```

С клиента WSL:

```bash
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health
curl --cacert ~/devops.crt -I https://devops.local/
```

`/health` проверяет процесс приложения без соединения с БД. Успешный запрос `/`
дополнительно проверяет подключение и запись в PostgreSQL. При 502 сначала проверить
`docker compose ps`, локальный curl на 127.0.0.1:5000, затем журналы приложения
и `/var/log/nginx/devops-site.error.log`, после этого параметры proxy_pass.

`docker compose down` удаляет контейнеры и сеть, сохраняя `app_db_data` и счётчик.
`down -v` удаляет и том: эта команда применялась только к свежему учебному счётчику
для обязательного опыта сброса. При обычной остановке её не применять. Существующий
проект, итоговый том и снимки сохраняются для контрольной №2 и следующих работ.

Аудит в `~/scripts/audit.sh` теперь содержит раздел [5] и 14 проверок:
активность docker, healthy у app-db-1, отсутствие привязок 5000/5432 вне 127.0.0.1,
права `.env` 600, плюс прежние десять условий. Запускать `sudo -v`, затем
`~/scripts/audit.sh; echo $?`. При запуске через sudo каталог приложения всё равно
определяется из home учётной записи devops, а не /root; допускается APP_DIR.
Проверка портов учитывает IPv4 и IPv6 и ошибку команды ss.

Отрицательный опыт: временно заменить публикацию на `5000:5000`, выполнить
`docker compose up -d`; ожидается ровно одна ошибка аудита и код 1. Сразу вернуть
`127.0.0.1:5000:5000`, пересоздать приложение и получить 14/14, код 0.
Не публиковать небезопасную временную конфигурацию в Git.

Снимок `05-docker-compose` создаётся после корректного выключения VM, без RAM,
после чего VM запускается снова. Снимок `04-nginx-https` сохраняется.
