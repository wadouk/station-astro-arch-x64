#!/usr/bin/env bash
# VM de test de la station (QEMU + UEFI), même ISO et même playbook que le mini PC.
#   vm/vm.sh iso      télécharge l'ISO Arch officielle et vérifie sa somme SHA256
#   vm/vm.sh disk     crée le disque (40 Go) et les variables UEFI
#   vm/vm.sh install  démarre sur l'ISO
#   vm/vm.sh run      démarre sur le disque installé
#   vm/vm.sh reset    supprime disque et variables UEFI
# Redirections : SSH localhost:2222 -> VM:22, VNC localhost:5901 -> VM:5900
# VM_DISPLAY=none vm/vm.sh run : sans fenêtre (VNC et SSH seulement)
set -euo pipefail

VM_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$VM_DIR/cache"
ISO_MIRROR="${ISO_MIRROR:-https://geo.mirror.pkgbuild.com/iso/latest}"
ISO_FILE="$CACHE_DIR/archlinux-x86_64.iso"
DISK_FILE="$CACHE_DIR/station.qcow2"
DISK_SIZE="40G"
VARS_FILE="$CACHE_DIR/OVMF_VARS.4m.fd"
VM_RAM="4096"
VM_CPUS="4"

_log() { printf '\e[1;34m==>\e[0m %s\n' "$*" >&2; }
_die() { printf '\e[1;31m[x]\e[0m %s\n' "$*" >&2; exit 1; }

_ovmf() {
    local name="$1" dir
    for dir in /usr/share/edk2/x64 /usr/share/edk2-ovmf/x64 /usr/share/OVMF; do
        [[ -f "$dir/$name" ]] && { echo "$dir/$name"; return; }
    done
    _die "$name introuvable : installer edk2-ovmf"
}

_iso() {
    install -d "$CACHE_DIR"
    _log "Téléchargement de l'ISO depuis $ISO_MIRROR"
    curl -fL --continue-at - -o "$ISO_FILE" "$ISO_MIRROR/archlinux-x86_64.iso"
    curl -fsSL -o "$CACHE_DIR/sha256sums.txt" "$ISO_MIRROR/sha256sums.txt"
    (cd "$CACHE_DIR" && grep ' archlinux-x86_64.iso$' sha256sums.txt | sha256sum -c -)
}

_disk() {
    install -d "$CACHE_DIR"
    [[ -f "$DISK_FILE" ]] && _die "$DISK_FILE existe déjà (vm/vm.sh reset pour repartir de zéro)"
    qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
    cp "$(_ovmf OVMF_VARS.4m.fd)" "$VARS_FILE"
}

_qemu() {
    [[ -f "$DISK_FILE" ]] || _die "Pas de disque : vm/vm.sh disk"
    local accel=(-enable-kvm -cpu host)
    if [[ ! -w /dev/kvm ]]; then
        printf '\e[1;33m[!]\e[0m /dev/kvm inaccessible : émulation logicielle (très lent)\n' >&2
        accel=(-cpu max)
    fi
    qemu-system-x86_64 "${accel[@]}" -machine q35 -m "$VM_RAM" -smp "$VM_CPUS" \
        -drive if=pflash,format=raw,readonly=on,file="$(_ovmf OVMF_CODE.4m.fd)" \
        -drive if=pflash,format=raw,file="$VARS_FILE" \
        -drive file="$DISK_FILE",if=none,id=hd0,format=qcow2 \
        -device virtio-blk-pci,drive=hd0,bootindex=2 \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:5901-:5900 \
        -vga virtio -display "${VM_DISPLAY:-gtk}" \
        "$@"
}

_install() {
    [[ -f "$ISO_FILE" ]] || _die "Pas d'ISO : vm/vm.sh iso"
    _qemu -drive file="$ISO_FILE",media=cdrom,if=none,id=cd0,readonly=on \
          -device ide-cd,drive=cd0,bootindex=1
}

_reset() {
    rm -f "$DISK_FILE" "$VARS_FILE"
    _log "Disque et variables UEFI supprimés (ISO conservée)"
}

case "${1:-}" in
    iso)     _iso ;;
    disk)    _disk ;;
    install) _install ;;
    run)     _qemu ;;
    reset)   _reset ;;
    *)       sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
