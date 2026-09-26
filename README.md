# astro-station-x64

Station d'astrophoto **sans écran** sur mini PC x86_64, décrite en code. Arch Linux + XFCE, pilotée par
Ansible depuis le portable. Les idées viennent d'[AstroArch](https://github.com/devDucks/astroarch)
(écran factice, x0vncserver sur `:0`, connexion automatique, Wi-Fi sans économie d'énergie, point d'accès
de terrain), réécrites de façon déclarative pour une machine x64.

KStars/Ekos, PHD2 et INDI tournent **sur la station**. Le portable ne sert qu'à regarder (VNC) et à
piloter la config (Ansible) : on peut l'éteindre en pleine séance.

## Principes

- **La station est jetable.** Tout ce qui la définit est ici. Réinstaller = ISO officielle + `make apply`.
- **Aucune modification sous `/usr`** : elle serait écrasée à la prochaine mise à jour du paquet. Tout passe par
  les répertoires de surcharge de `/etc` (`sshd_config.d`, `lightdm.conf.d`, `xorg.conf.d`,
  `NetworkManager/conf.d`, `udev/rules.d`, systemd `*.service.d`).
- **Les `.pacnew` sont signalés** à chaque exécution. Les fusionner avec `sudo pacdiff`.
- **La dérive se voit** : `make check` montre ce qu'Ansible changerait.
- **Snapshot avant chaque mise à jour** (btrfs + snapper + snap-pac). Si une mise à jour casse INDI, démarrer
  sur le snapshot depuis le menu GRUB (grub-btrfs).
- **Secrets dans ansible-vault**, jamais en clair dans git.

## Arborescence

| Chemin | Rôle |
|---|---|
| `archinstall/` | configuration d'installation Arch (base versionnée + générateur qui y ajoute la clé SSH) |
| `roles/base` | paquets, nom de machine, fuseau, pas de mise en veille, USB toujours alimenté, chrony, IgnorePkg, rapport des .pacnew |
| `roles/ssh` | clé du portable, sshd durci (sans root ni mot de passe), redirections TCP/X11, `<nom>.local` (avahi) |
| `roles/network` | Wi-Fi sans économie d'énergie, point d'accès de terrain (fichier NetworkManager déclaratif) |
| `roles/headless_vnc` | connexion auto LightDM, écran factice, x0vncserver (service utilisateur), pas de verrouillage |
| `roles/snapshots` | snapper, snap-pac, grub-btrfs |
| `roles/astro` | kstars, libindi, stellarsolver, paquets AUR (utilisateur dédié `aur_builder` + paru) |
| `update.yml` | `pacman -Syu` + AUR, puis reconvergence |
| `vm/vm.sh` | VM de test QEMU/UEFI |

## Préparer le portable (une fois)

```bash
make deps                                  # collections Ansible dans ./collections
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519
# Secrets de la vraie station
openssl rand -base64 32 > .vault-pass && chmod 600 .vault-pass
cp group_vars/stations/vault.yml.example group_vars/stations/vault.yml
$EDITOR group_vars/stations/vault.yml
ansible-vault encrypt --vault-password-file .vault-pass group_vars/stations/vault.yml
```
Garde une copie de `.vault-pass` en lieu sûr (gestionnaire de mots de passe) : sans elle, le coffre est illisible.

## Tester dans la VM

```bash
make vm-iso vm-disk             # ISO officielle vérifiée + disque 40 Go
make archinstall-config-vm      # génère archinstall/out/ (mot de passe « astro »)
make vm-serve                   # terminal 1 : sert la config à la VM
make vm-install                 # terminal 2 : démarre la VM sur l'ISO
```
Dans la VM (console de l'ISO) :
```bash
archinstall --config-url http://10.0.2.2:8000/user_configuration.json \
            --creds-url  http://10.0.2.2:8000/user_credentials.json
```
Tout est prérempli sauf le **disque**. Dans le menu disque, choisir :
- le disque virtuel, disposition par défaut ;
- système de fichiers **btrfs**, avec les sous-volumes par défaut ;
- snapshots **Snapper**.

Puis lancer l'installation, éteindre la VM, et :
```bash
make vm-run                     # démarre sur le disque
make ping                       # HOST=vm par défaut
make apply                      # converge la VM
make check                      # doit ne plus rien changer : c'est le test d'idempotence
vncviewer localhost::5901       # bureau XFCE de la VM, mot de passe VNC de host_vars/vm.yml
```
Redémarrer la VM après le premier `make apply` pour vérifier la connexion auto, l'écran factice (la fenêtre
QEMU reste noire) et le VNC.

## Installer le mini PC

1. Clé USB avec l'ISO officielle (`vm/cache/archlinux-x86_64.iso`, déjà vérifiée).
2. `make archinstall-config` (demande le mot de passe de l'utilisateur, le même que `vault_become_password`).
3. Servir `archinstall/out/` sur le réseau local le temps de l'installation :
   `python3 -m http.server 8000 --directory archinstall/out` (Ctrl+C juste après, les identifiants sont en clair).
   Autre solution : copier les deux fichiers sur une clé USB et utiliser `--config` / `--creds`.
4. Sur le mini PC, depuis l'ISO :
   `archinstall --config-url http://<ip-portable>:8000/user_configuration.json --creds-url http://<ip-portable>:8000/user_credentials.json`.
   Disque : btrfs + Snapper, comme dans la VM.
5. Au redémarrage : `make ping HOST=station` puis `make apply HOST=station`, redémarrer, débrancher l'écran.

## Au quotidien

| Besoin | Commande |
|---|---|
| Voir la dérive | `make check HOST=station` |
| Réappliquer | `make apply HOST=station` |
| Mettre à jour (jamais un soir de ciel clair) | `make update HOST=station`, puis `sudo pacdiff` si des .pacnew sont signalés, puis un test avec les simulateurs INDI |
| Épingler kstars/INDI pendant la saison | `pacman_ignore: [kstars, libindi]` dans `group_vars/stations/main.yml`, puis `make apply` |
| Revenir en arrière après une mise à jour ratée | redémarrer, menu GRUB « Arch Linux snapshots », choisir le snapshot pre-pacman |
| Retrouver l'écran physique | `vnc_dummy_screen: false`, `make apply`, redémarrer |
| VNC seulement par tunnel SSH | `vnc_localhost_only: true`, puis `ssh -L 5900:localhost:5900 astro@astro-station.local` |

## Pourquoi Ansible

- **NixOS** élimine la dérive par construction, mais c'est une autre distribution, et les SDK caméra
  propriétaires y sont pénibles à empaqueter.
- **aconfmgr** (spécifique Arch) capture *tout* l'état, y compris ce qu'on n'a pas déclaré. Il ne gère qu'une
  machine et s'exécute sur la machine elle-même.
- **pyinfra** : même modèle qu'Ansible, en Python, avec un écosystème plus petit (AUR notamment).
- **Salt, Puppet, Chef** : ils demandent un agent, c'est trop lourd pour une machine.

Ansible fonctionne sans agent, en SSH depuis le portable. Il a des modules pacman, AUR et systemd,
`--check --diff` pour voir la dérive, et ansible-vault pour les secrets. C'est aussi une compétence réutilisable.
