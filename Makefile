HOST ?= vm
VAULT_ARGS := $(if $(wildcard .vault-pass),--vault-password-file .vault-pass,)
PLAYBOOK := ansible-playbook $(VAULT_ARGS) --limit $(HOST)

.PHONY: help deps syntax ping check apply update archinstall-config archinstall-config-vm \
        vm-iso vm-disk vm-install vm-run vm-serve vm-reset

help:
	@echo "Station :   make check|apply|update HOST=vm|station"
	@echo "Outils :    make deps syntax ping"
	@echo "Install :   make archinstall-config[-vm]"
	@echo "VM :        make vm-iso vm-disk vm-serve vm-install vm-run vm-reset"

deps:
	ansible-galaxy collection install -r requirements.yml -p collections

syntax:
	ansible-playbook $(VAULT_ARGS) --syntax-check site.yml update.yml

ping:
	ansible $(VAULT_ARGS) $(HOST) -m ansible.builtin.ping

# Dérive : ce qui changerait, sans rien toucher
check:
	$(PLAYBOOK) site.yml --check --diff

apply:
	$(PLAYBOOK) site.yml --diff

# pacman -Syu + AUR (snapshots snap-pac avant/après) puis reconvergence
update:
	$(PLAYBOOK) update.yml --diff

archinstall-config:
	archinstall/generate.sh

archinstall-config-vm:
	archinstall/generate.sh --vm

vm-iso:
	vm/vm.sh iso
vm-disk:
	vm/vm.sh disk
vm-install:
	vm/vm.sh install
vm-run:
	vm/vm.sh run
vm-serve:
	vm/vm.sh serve
vm-reset:
	vm/vm.sh reset
