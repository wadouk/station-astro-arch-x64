HOST ?= vm
# IP=<adresse> : joindre la station par son IP tant que <nom>.local n'existe pas (premier passage)
IP ?=
# Port SSH de l'environnement live (22 sur le mini PC, 2222 pour la VM)
PORT ?= 22
VAULT_ARGS := $(if $(wildcard .vault-pass),--vault-password-file .vault-pass,)
HOST_ARGS := $(if $(IP),-e ansible_host=$(IP),)
PLAYBOOK := ansible-playbook $(VAULT_ARGS) --limit $(HOST) $(HOST_ARGS)
# L'ISO live change de clé d'hôte à chaque démarrage : ne pas polluer known_hosts
LIVE_SSH_OPTS := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

.PHONY: help deps hooks syntax ping check apply update archinstall-config archinstall-config-vm \
        live-ssh push-config vm-live-ssh vm-push-config \
        vm-iso vm-disk vm-install vm-run vm-reset

help:
	@echo "Station :   make check|apply|update HOST=vm|station [IP=<adresse>]"
	@echo "Outils :    make deps syntax ping"
	@echo "Install :   make archinstall-config[-vm]"
	@echo "Live ISO :  make push-config|live-ssh IP=<adresse>   (VM : make vm-push-config|vm-live-ssh)"
	@echo "VM :        make vm-iso vm-disk vm-install vm-run vm-reset"

# Première commande après un clone : collections Ansible + garde-fou des secrets (.githooks/pre-commit)
deps: hooks
	ansible-galaxy collection install -r requirements.yml -p collections

hooks:
	git config core.hooksPath .githooks

syntax:
	ansible-playbook $(VAULT_ARGS) --syntax-check site.yml update.yml

ping:
	ansible $(VAULT_ARGS) $(HOST) $(HOST_ARGS) -m ansible.builtin.ping

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

# Copie la config archinstall dans l'ISO live (root, après `passwd` sur la console)
push-config:
	@test -n "$(IP)" || { echo "IP=<adresse du mini PC> requis"; exit 1; }
	@test -f archinstall/out/user_configuration.json || { echo "make archinstall-config d'abord"; exit 1; }
	scp $(LIVE_SSH_OPTS) -P $(PORT) archinstall/out/user_configuration.json archinstall/out/user_credentials.json root@$(IP):

live-ssh:
	@test -n "$(IP)" || { echo "IP=<adresse du mini PC> requis"; exit 1; }
	ssh $(LIVE_SSH_OPTS) -p $(PORT) root@$(IP)

vm-push-config:
	$(MAKE) push-config IP=127.0.0.1 PORT=2222

vm-live-ssh:
	$(MAKE) live-ssh IP=127.0.0.1 PORT=2222

vm-iso:
	vm/vm.sh iso
vm-disk:
	vm/vm.sh disk
vm-install:
	vm/vm.sh install
vm-run:
	vm/vm.sh run
vm-reset:
	vm/vm.sh reset
