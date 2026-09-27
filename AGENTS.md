# AGENTS.md

Tout est dans le [README](README.md) : principes, rôles, installation, VM de test, sauvegarde.

Règles à respecter en plus :
- Jamais de secret versionné : `vault.yml`, `.vault-pass`, `hardware.yml`, `locale.yml` restent hors de git
  (`.githooks/pre-commit`, activé par `make deps`, refuse un coffre non chiffré ou `.vault-pass`).
- Toute modification se teste sur la VM (`make apply`, puis `make apply` doit donner `changed=0`).
- Rien sous `/usr` sur la station : uniquement les répertoires de surcharge de `/etc`.
