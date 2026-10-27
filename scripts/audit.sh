#!/usr/bin/env bash
# Run on devops-vm after sudo -v, or as sudo bash scripts/audit.sh.
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        ((PASS+=1))
    else
        printf '  [FAIL] %s (expected: %s; actual: %s)\n' "$desc" "$expected" "$actual"
        ((FAIL+=1))
    fi
}
printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
sshd_config="$(sudo -n /usr/sbin/sshd -T 2>/dev/null)" || sshd_config=''
setting() { awk -v key="$1" '$1==key {print $2; exit}' <<< "$sshd_config"; }
echo '[1] SSH service'
check 'Root login disabled' no "$(setting permitrootlogin)"
check 'Password authentication disabled' no "$(setting passwordauthentication)"
ports="$(awk '$1=="port" {print $2}' <<< "$sshd_config")"
nonstandard=true
if [[ -z "$ports" ]]; then nonstandard=false; fi
while IFS= read -r port; do
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port==22 || port<1 || port>65535)); then
        nonstandard=false
    fi
done <<< "$ports"
check 'Every SSH port differs from 22' true "$nonstandard"
check 'MaxAuthTries equals 3' 3 "$(setting maxauthtries)"
echo '[2] Firewall'
ufw_config="$(sudo -n ufw status verbose 2>/dev/null)" || ufw_config=''
check 'Firewall active' active "$(awk '/^Status:/ {print $2}' <<< "$ufw_config")"
check 'Incoming policy is deny' deny "$(awk '/^Default:/ {print $2}' <<< "$ufw_config")"
echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo '[4] Web server'
check 'Nginx is active' active "$(systemctl is-active nginx 2>/dev/null)"
sudo -n nginx -t >/dev/null 2>&1
check 'Nginx configuration is valid' 0 "$?"
MIN_DAYS="${CERT_MIN_DAYS:-30}"
cert_status=1
if [[ "$MIN_DAYS" =~ ^[0-9]+$ ]] && (( MIN_DAYS <= 20000 )); then
    openssl x509 -in /etc/ssl/certs/devops.crt -noout \
        -checkend "$((10#$MIN_DAYS * 86400))" >/dev/null 2>&1
    cert_status=$?
fi
check "Certificate valid for at least ${MIN_DAYS} days" 0 "$cert_status"
safe=false
world_writable="$(find /var/www/devops-site -perm -o+w -print 2>/dev/null)"
find_status=$?
key_mode="$(sudo -n stat -c '%a:%U' /etc/ssl/private/devops.key 2>/dev/null)"
if (( find_status == 0 )) && [[ -z "$world_writable" && "$key_mode" == '600:root' ]]; then
    safe=true
fi
check 'No world-writable site paths; TLS key 600:root' true "$safe"

echo '[5] Containerization'
check 'Docker is active' active "$(systemctl is-active docker 2>/dev/null)"
check 'PostgreSQL container is healthy' healthy \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"
socket_list="$(ss -H -tln 2>/dev/null)"
socket_status=$?
local_ports=false
if (( socket_status == 0 )) && awk '
    $4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:(5000|5432)$/ {bad=1}
    END {exit bad ? 1 : 0}
' <<< "$socket_list"; then
    local_ports=true
fi
check 'Ports 5000 and 5432 listen only on 127.0.0.1 or are absent' true "$local_ports"
APP_DIR="${APP_DIR:-$(getent passwd devops | cut -d: -f6)/app}"
check 'Server .env permissions equal 600' 600 "$(stat -c '%a' "$APP_DIR/.env" 2>/dev/null)"
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
