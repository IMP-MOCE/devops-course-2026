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
