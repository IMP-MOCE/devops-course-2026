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
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
