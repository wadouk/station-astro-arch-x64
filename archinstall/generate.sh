#!/usr/bin/env bash
# Génère la configuration archinstall dans archinstall/out/ :
#   - user_configuration.json : base commune + nom de machine + clé SSH du portable
#   - user_credentials.json   : utilisateur sudo (mot de passe en clair, fichier non versionné)
# Usage : archinstall/generate.sh [--vm]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/archinstall/out"
BASE_CONFIG="$REPO_DIR/archinstall/user_configuration.base.json"
PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
VM_PASSWORD="astro"

_log() { printf '\e[1;34m==>\e[0m %s\n' "$*" >&2; }
_die() { printf '\e[1;31m[x]\e[0m %s\n' "$*" >&2; exit 1; }

# Lit une clé simple de group_vars/stations/main.yml (ou host_vars/vm.yml)
_var() {
    awk -F': *' -v k="$1" '$1==k {gsub(/"/, "", $2); print $2; exit}' "$2"
}

command -v jq >/dev/null || _die "jq requis"
[[ -f "$PUBKEY_FILE" ]] || _die "Clé publique absente ($PUBKEY_FILE) : ssh-keygen -t ed25519"

station_user="$(_var station_user "$REPO_DIR/group_vars/stations/main.yml")"
hostname="$(_var station_hostname "$REPO_DIR/group_vars/stations/main.yml")"
if [[ "${1:-}" == "--vm" ]]; then
    hostname="$(_var station_hostname "$REPO_DIR/inventory/host_vars/vm.yml")"
    password="$VM_PASSWORD"
else
    read -rsp "Mot de passe de $station_user sur la station : " password; echo >&2
    read -rsp "Confirmation : " password2; echo >&2
    [[ "$password" == "$password2" ]] || _die "Mots de passe différents"
fi
pubkey="$(cat "$PUBKEY_FILE")"

install -d -m 700 "$OUT_DIR"

# La clé du portable est posée dès l'installation : Ansible se connecte sans étape manuelle
jq --arg host "$hostname" --arg user "$station_user" --arg key "$pubkey" '
    .hostname = $host
    | .custom_commands += [
        "install -d -m 700 -o \($user) -g \($user) /home/\($user)/.ssh",
        "printf \"%s\\n\" \"\($key)\" > /home/\($user)/.ssh/authorized_keys",
        "chown \($user):\($user) /home/\($user)/.ssh/authorized_keys",
        "chmod 600 /home/\($user)/.ssh/authorized_keys"
      ]
' "$BASE_CONFIG" > "$OUT_DIR/user_configuration.json"

jq -n --arg user "$station_user" --arg pw "$password" '
    {users: [{username: $user, "!password": $pw, sudo: true, groups: []}]}
' > "$OUT_DIR/user_credentials.json"
chmod 600 "$OUT_DIR/user_credentials.json"

_log "Écrit : $OUT_DIR/user_configuration.json (hôte $hostname, utilisateur $station_user)"
_log "Écrit : $OUT_DIR/user_credentials.json (non versionné)"
