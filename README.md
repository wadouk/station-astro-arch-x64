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
| `roles/snapshots` | snapper (racine seulement), snap-pac, grub-btrfs |
| `roles/gps` | appliqué si `gps_device` est renseigné : gpsd sur le chemin stable du GPS, heure système par chrony (refclock SHM, comme AstroArch) |
| `roles/memory` | zram à la taille de la RAM, réglages vm.* pour zram, earlyoom qui épargne la chaîne d'acquisition |
| `roles/astro` | kstars, libindi, stellarsolver, PHD2 (AUR via `aur_builder` + paru), pilotes INDI tiers (PKGBUILD généré depuis `hardware.yml`), ModemManager masqué |
| `update.yml` | `pacman -Syu` + AUR, puis reconvergence |
| `vm/vm.sh` | VM de test QEMU/UEFI |

## Réglages personnels

Deux fichiers non versionnés, chargés automatiquement ; tout le reste est le standard du projet.

| Fichier | Contenu | Sans le fichier |
|---|---|---|
| `group_vars/stations/locale.yml` | fuseau horaire, disposition du clavier | UTC, QWERTY US |
| `group_vars/stations/hardware.yml` | pilotes INDI tiers, GPS, logiciels astro en plus | socle kstars/libindi/stellarsolver |

```bash
cp group_vars/stations/locale.yml.example group_vars/stations/locale.yml
cp group_vars/stations/hardware.yml.example group_vars/stations/hardware.yml
```
`make archinstall-config` lit aussi `locale.yml` (clavier et fuseau de l'installation).

## Matériel

Le matériel et les logiciels astro propres à chaque station sont dans `group_vars/stations/hardware.yml`.
| Variable | Rôle |
|---|---|
| `indi_3rdparty_drivers` | pilotes INDI tiers à compiler : `name` = option `WITH_<name>` d'indi-3rdparty, `depends` = paquets nécessaires |
| `gps_device` | chemin stable du GPS (`ls -l /dev/serial/by-id/` sur la station) ; vide = pas de GPS, rôle `gps` non appliqué |
| `astro_extra_packages` / `astro_aur_packages` | logiciels en plus de kstars/libindi/stellarsolver (dépôts officiels / AUR) |

Beaucoup de pilotes sont déjà dans libindi (dépôts officiels, rien à compiler), par exemple MoonLite
(`indi_moonlite_focus`) ou CheapoDC (`indi_cheapodc`). Liste complète : `ls /usr/bin/indi_*` sur la station.

**Pourquoi un PKGBUILD généré plutôt que les paquets AUR `libindi-*`.** Ces paquets exigent
`libindi=<version exacte>` et décrochent à chaque mise à jour de libindi dans les dépôts officiels.
`roles/astro/templates/PKGBUILD.j2` compile les pilotes listés depuis indi-3rdparty, contre la libindi
installée. Modifier la liste, ou la version (`indi_3rdparty_version` et `indi_3rdparty_sha256` dans
`roles/astro/defaults/main.yml`), déclenche une recompilation au `make apply` suivant.

La détection automatique de gpsd est coupée : elle reconnaît les puces CP210x des câbles EQDIR et prendrait
le port de la monture. Le GPS est déclaré par son chemin stable.

## Préparer le portable (une fois)

```bash
make deps                                  # collections Ansible + garde-fou des secrets (hook git)
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519
# Secrets de la vraie station
openssl rand -base64 32 > .vault-pass && chmod 600 .vault-pass
cp group_vars/stations/vault.yml.example group_vars/stations/vault.yml
$EDITOR group_vars/stations/vault.yml
ansible-vault encrypt --vault-password-file .vault-pass group_vars/stations/vault.yml
```
Garde une copie de `.vault-pass` en lieu sûr (gestionnaire de mots de passe) : sans elle, le coffre est illisible.

`make deps` active `.githooks/pre-commit` (git n'active jamais les hooks d'un clone de lui-même). Le hook refuse
tout commit de `.vault-pass`, ou d'un `vault*.yml` non chiffré. Modifie le coffre avec `ansible-vault edit`,
jamais `decrypt`.

## Comment se déroule l'installation

L'installation part de l'**ISO Arch officielle**. Une ISO Manjaro ne convient pas : `archinstall` n'y existe
pas, et installer Arch depuis Manjaro mélangerait deux bases. L'environnement live de l'ISO Arch **lance
sshd d'office**. Il suffit de donner un mot de passe à root sur la console pour piloter toute l'installation
depuis le portable, avec le copier-coller.

La config archinstall générée installe openssh, active sshd et dépose la clé du portable dans
`~/.ssh/authorized_keys`. **Au premier démarrage, SSH marche donc déjà**, et Ansible prend le relais.

| Étape | Où | Quoi |
|---|---|---|
| 1 | portable | générer la config archinstall, préparer le coffre |
| 2 | console du live | clavier, réseau, `passwd` (root du live uniquement) |
| 3 | portable → live (SSH) | copier la config, lancer `archinstall`, choisir le disque |
| 4 | portable → système installé | `ssh astro@…` sans mot de passe, puis Ansible |
| 5 | portable | redémarrage sans écran, VNC |

Le même déroulé sert pour la VM (d'abord) et pour le mini PC (ensuite).

## Tester dans la VM

```bash
make vm-iso vm-disk             # ISO officielle vérifiée + disque 40 Go
make archinstall-config-vm      # archinstall/out/ (mot de passe « astro »)
make vm-install                 # démarre la VM sur l'ISO (fenêtre QEMU)
```
Dans la fenêtre QEMU, une fois la console de l'ISO affichée :
```bash
loadkeys fr                     # seulement pour un clavier AZERTY (l'ISO est en QWERTY US)
passwd                          # mot de passe root du live, par exemple « live »
```
Puis depuis le portable :
```bash
make vm-push-config             # scp de la config dans l'ISO (localhost:2222)
make vm-live-ssh                # SSH dans l'ISO
archinstall --config user_configuration.json --creds user_credentials.json
```
Tout est prérempli sauf le **disque**. Dans *Disk configuration* :
1. *Partitioning* → **Use a best-effort default partition layout** → le disque virtuel.
2. Système de fichiers **btrfs**.
3. « Would you like to use BTRFS subvolumes with a default structure? » → **Yes** (`@`, `@home`, `@log`, `@pkg`).
4. Compression : **Use compression** (zstd).
5. **Ne pas cocher** *Btrfs snapshots*. C'est le rôle `snapshots` qui installe snapper, pour la racine
   seulement : l'option d'archinstall ajoute aussi une config `/home` à snapshots horaires, qui retiendrait
   les images supprimées. Sur la VM de test, cette option n'a d'ailleurs pas été appliquée.

La partition `/boot` proposée (FAT32, ~1 Gio) est la partition EFI qu'utilise GRUB : la garder. Évite le
partitionnement manuel. Il ne crée pas de sous-volumes, donc pas de snapshots, à moins de les déclarer
un par un (`@` → `/`, `@home` → `/home`, `@log` → `/var/log`, `@pkg` → `/var/cache/pacman/pkg`).

Puis *Install*. À la fin, `poweroff`, et :
```bash
make vm-run                     # démarre sur le disque installé
make ping                       # HOST=vm par défaut, SSH par clé
make apply                      # converge la VM
make check                      # doit ne plus rien changer : c'est le test d'idempotence
vncviewer localhost::5901       # bureau XFCE de la VM, mot de passe VNC de host_vars/vm.yml
```
Redémarrer la VM après le premier `make apply` pour vérifier la connexion auto, l'écran factice (la fenêtre
QEMU reste noire) et le VNC.

## Installer le mini PC

**1. Sur le portable**
```bash
make archinstall-config         # demande le mot de passe d'astro (= vault_become_password du coffre)
lsblk                           # repérer la clé USB, ex. /dev/sdb
sudo dd if=vm/cache/archlinux-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
`dd` efface la clé. Pour garder plusieurs ISO sur la même clé, utiliser Ventoy.

**2. Sur le mini PC** (écran, clavier, câble Ethernet de préférence)
- BIOS : démarrage **UEFI**, **Secure Boot désactivé**, démarrage sur la clé (F7, F11 ou Suppr selon la carte).
- Console du live :
  ```bash
  loadkeys fr                   # seulement pour un clavier AZERTY
  ip -4 a                       # noter l'IP ; en Wi-Fi : iwctl station wlan0 connect <SSID>
  passwd                        # root du live uniquement
  ```

**3. Depuis le portable**
```bash
make push-config IP=<ip-minipc>
make live-ssh IP=<ip-minipc>
archinstall --config user_configuration.json --creds user_credentials.json
```
Disque : même procédure que dans la VM (disposition *best-effort*, btrfs, sous-volumes par défaut → **Yes**,
*Btrfs snapshots* non coché), sur le SSD NVMe. **Le SSD est entièrement
effacé.** À la fin : `poweroff`, retirer la clé USB, rallumer.

**4. Premier démarrage.** L'écran de connexion XFCE s'affiche : la connexion auto n'est pas encore
configurée, c'est Ansible qui s'en charge. SSH est déjà actif avec la clé du portable :
```bash
ssh-keygen -R <ip-minipc>       # si cette IP a déjà servi (ancienne install, live ISO)
ssh astro@<ip-minipc>           # entre sans mot de passe ; accepter la clé d'hôte
```
Au premier passage, `astro-station.local` n'existe pas encore (avahi est installé par Ansible) : on passe l'IP.
```bash
make ping  HOST=station IP=<ip-minipc>
make apply HOST=station IP=<ip-minipc>
ssh astro@astro-station.local   # accepter la clé d'hôte sous ce nom
```

**5. Passage sans écran.** `ssh astro@astro-station.local sudo reboot`, débrancher l'écran, puis :
```bash
vncviewer astro-station.local::5900
make check HOST=station         # plus rien à changer
```

## Au quotidien

| Besoin | Commande |
|---|---|
| Voir la dérive | `make check HOST=station` |
| Réappliquer | `make apply HOST=station` |
| Mettre à jour (jamais un soir de ciel clair) | `make update HOST=station`, puis `sudo pacdiff` si des .pacnew sont signalés, puis un test avec les simulateurs INDI |
| Épingler kstars/INDI pendant la saison | `pacman_ignore: [kstars, libindi]` dans `group_vars/stations/main.yml`, puis `make apply` |
| Revenir en arrière après une mise à jour ratée | redémarrer, menu GRUB « Arch Linux snapshots », choisir le snapshot pre-pacman |
| Ajouter/retirer un réseau Wi-Fi | `ansible-vault edit --vault-password-file .vault-pass group_vars/stations/vault.yml` (liste `vault_wifi_networks`), puis `make apply HOST=station` |
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
