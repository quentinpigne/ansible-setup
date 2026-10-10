# Setup new operating systems using Ansible

Configuration automatisee de plusieurs machines : un Mac, un serveur Ubuntu, une
distro Ubuntu sous WSL (contexte pro), et a venir un poste Linux perso.

## Structure

La configuration d'une machine se compose sur **trois axes independants**,
materialises par des groupes d'inventaire :

| Axe          | Valeurs                     | Determine                          |
| ------------ | --------------------------- | ---------------------------------- |
| **contexte** | `perso` / `pro`             | la politique (DNS, proxy)          |
| **profil**   | `desktop` / `server` / `wsl`| l'usage (hostname, sshd, wsl.conf) |
| **OS**       | `mac` / `linux`             | l'installation (brew, apt)         |

| Machine       | contexte | profil    | OS      |
| ------------- | -------- | --------- | ------- |
| `mac-perso`   | perso    | desktop   | mac     |
| `ubuntu01`    | perso    | server    | linux   |
| `wsl-kaizen`  | pro      | wsl       | linux   |
| `linux-perso` | perso    | desktop   | linux   | *(a venir)*

Chaque axe apporte sa couche. La composition vit dans `group_vars/all.yml`
sous forme de listes, et le role `base` les enchaine :

```yaml
# group_vars/all.yml
base_roles: >-
  {{ (base_roles_by_profile[profile] | default([]))     # hostname, ssh, wsl.conf
     + (base_roles_by_os[os] | default([]))             # paquets, core_tools
     + base_roles_personal                              # git, zsh, dotfiles, fonts
     + (base_roles_by_context[context] | default([])) }}   # DNS, proxy

# roles/base/tasks/main.yml
- name: Apply the base configuration
  ansible.builtin.include_role:
    name: "{{ base_role }}"
  loop: "{{ base_roles | reject('in', base_skip) | list }}"
  loop_control:
    loop_var: base_role
```

Ce qui donne, machine par machine :

```
mac-perso    hostname preflight homebrew appstore core_tools iterm2
             macos_settings git zsh dotfiles fonts dns
ubuntu01     hostname ssh apt_base core_tools git zsh dotfiles fonts dns
wsl-kaizen   wsl_conf apt_base core_tools git zsh dotfiles fonts
```

L'ordre compte : le profil pose l'identite, l'OS installe, le contexte applique
la politique. Un quatrieme axe plus fin, `distro_family` (`Darwin`, `Debian`,
...), est **infere** des facts et sert au dispatch dans les roles -- voir plus bas.

### Ou mettre une configuration

Quatre emplacements, selon ce dont la configuration depend :

| La config depend de...        | Ou la mettre                                | Exemple                        |
| ----------------------------- | ------------------------------------------- | ------------------------------ |
| du **contexte** seul          | `group_vars/perso.yml` / `pro.yml`          | identite Git                   |
| de l'**OS** seul              | `group_vars/mac.yml` / `linux.yml`          | reglages iTerm2                |
| du **profil** seul            | `group_vars/desktop.yml` / `server.yml` / `wsl.yml` | hostname predefini     |
| de **deux axes a la fois**    | un `X_by_context` dans le fichier de l'axe principal | casks Homebrew, Dock  |
| d'un axe, mais c'est un **role entier** | une liste `base_roles_by_*` (`group_vars/all.yml`) | DNS (perso), sshd (server) |

Ansible ne sait pas exprimer une intersection de groupes dans `group_vars` :
`mac.yml` s'applique a tout Mac, `perso.yml` a toute machine personnelle, mais
rien ne vise « un Mac personnel ». D'ou la quatrieme ligne : la partie qui
depend du contexte est **indexee par sa valeur**, dans le fichier de l'OS.

Deux formes, selon le type de donnee :

```yaml
# une LISTE -> on concatene (le role fait la somme)
homebrew_context: "{{ homebrew_by_context[context] | default({}) }}"
homebrew_by_context:
  perso: { casks: [minecraft, steam, openemu] }
  pro:   { casks: [microsoft-office, microsoft-teams] }

# un DICTIONNAIRE -> on fusionne (les cles du contexte gagnent)
dock: "{{ dock_common | combine(dock_by_context[context] | default({})) }}"
dock_common:
  defaults: [...]              # identique partout
  display_applications: []     # valeur plancher
dock_by_context:
  perso: { display_applications: [..., Steam, OpenEmu, Blender] }
  pro:   { display_applications: [..., Outlook, Teams, Word] }
```

Resultat sur un Mac professionnel : ni jeux installes, ni Steam dans le Dock,
ni le OneDrive personnel dans les dossiers epingles.

```
mac-perso  -> 20 casks | Dock : 11 apps, OneDrive-Personnel epingle
mac-pro    -> 11 casks | Dock : 10 apps, pas de OneDrive personnel
```

Les valeurs plancher (`display_applications: []`) evitent qu'un contexte absent
de l'index provoque une erreur de variable indefinie.

### Ciblage

`./apply.sh` cible par defaut la machine courante :

```sh
./apply.sh                      # cette machine
./apply.sh --tags docker        # cette machine, un outil en plus
./apply.sh ubuntu01             # une autre machine
./apply.sh perso --tags dns     # un groupe, avec des tags
```

La cible est **toujours explicite**. Lancer `ansible-playbook site.yml` sans
`--limit` viserait les trois machines a la fois ; pire, un hote declare
`ansible_connection: local` designe la machine courante quel que soit son nom,
donc `wsl-kaizen` lance depuis le Mac appliquerait la configuration pro/WSL au
Mac. Le role `distro_check` refuse ce cas, et `apply.sh` l'evite.

Sans argument, `apply.sh` retient l'hote en connexion locale dont l'OS declare
correspond a celui de la machine -- le meme critere que le garde-fou.

Les groupes d'axes restent utilisables comme cible (`perso`, `server`, `mac`).
Pour croiser deux axes, la syntaxe Ansible s'applique : `:&` pour ET, `:` pour
OU, `:!` pour SAUF.

```sh
./apply.sh 'perso:&linux'       # machines personnelles sous Linux
```

### Ajouter une machine

Trois etapes, sans ecrire une ligne de role ni de playbook.

**1. La declarer dans un groupe de chacun des trois axes** (`inventory/hosts.yml`) :

```yaml
    pro:       { hosts: { mac-boulot: } }           # contexte
    desktop:   { hosts: { mac-boulot: } }           # profil
    mac:       { hosts: { mac-boulot: {ansible_connection: local} } }   # OS
```

Les trois sont obligatoires : le role `base` refuse une machine incomplete en
nommant les axes manquants.

**2. Sa configuration propre** (`inventory/host_vars/mac-boulot.yml`) :

```yaml
hostname: MacBook-Boulot     # facultatif : voir la section Hostname
extras:                      # installations en plus de la base
  - docker
  - nvm
```

**3. L'appliquer** :

```sh
./apply.sh mac-boulot                  # base + extras declares
./apply.sh mac-boulot --tags rust      # avec un extra ponctuel en plus
```

Tout le reste se deduit : identite Git, listes de paquets, DNS, hostname,
branche dotfiles, couches de base. Exemple pour la declaration ci-dessus :

```
context=pro  profile=desktop  os=mac
git.email = quentin.pigne@kaizen-solutions.net     (contexte pro)
casks     = 11, dont microsoft-office             (socle mac + contexte pro)
           ni Steam ni Minecraft                  (reserves au contexte perso)
```

Sur une machine **vierge** (ni git, ni Ansible, ni le depot), `bootstrap.sh`
enchaine les trois etapes tout seul -- voir Installation.

### Choisir finement ce qui s'installe

La base n'est pas un bloc monolithique : c'est une **liste de roles**, assemblee
a partir des trois axes puis filtree. Elle s'inspecte :

```sh
ansible ubuntu01 -m debug -a var=base_roles
# hostname, ssh, apt_base, core_tools, git, zsh, dotfiles, fonts, dns
```

(`ansible-inventory --host` ne convient pas ici : il affiche le template, pas
la liste resolue.)

Quatre leviers, du plus durable au plus ponctuel :

| Besoin                                | Levier                        | Ou                |
| ------------------------------------- | ----------------------------- | ----------------- |
| ajouter un outil a une machine        | `extras: [docker, nvm]`       | `host_vars`       |
| **retirer** un role de la base        | `base_skip: [dotfiles, git]`  | `host_vars`       |
| installer un seul outil, sans la base | `--tags docker`               | ligne de commande |
| ecarter un role une seule fois        | `--skip-tags fonts`           | ligne de commande |

`base_skip` est **declaratif et persistant**, contrairement a `--skip-tags`
qu'il faudrait repasser a chaque execution :

```yaml
# une VM de travail : les outils, pas l'identite
base_skip: [git, zsh, dotfiles, fonts]

# un Mac dont Ansible ne doit pas toucher l'interface
base_skip: [macos_settings, iterm2]

# un serveur ou les DNS sont geres ailleurs
base_skip: [dns]
```

Effet mesure sur le Mac :

```
base normale   hostname preflight homebrew appstore core_tools iterm2
               macos_settings git zsh dotfiles fonts dns

base_skip:     hostname preflight homebrew appstore core_tools
[dotfiles,     zsh fonts dns
 git,
 macos_settings]
```

Une exclusion qui ne correspond a aucun role de la base est refusee, avec la
liste de ce qui est disponible -- une faute de frappe passerait sinon inapercue :

```
base_skip contient des roles absents de la base de mac-perso : dotfile,
macos_setting. Base de cette machine : hostname, preflight, homebrew, ...
```

Pour **ajouter** un role a la base plutot qu'aux extras, la composition
elle-meme est surchargeable par `host_vars` : `base_roles_personal`,
`base_roles_by_os`, `base_roles_by_context`.

Un seul outil, sans rien declarer ni jouer la base :

```sh
./apply.sh vm-boulot --tags docker
```

Seuls les garde-fous (`distro_check`) et le role demande s'executent.

### Runner GitLab

L'extra `gitlab_runner` installe `gitlab-runner` depuis le depot officiel
GitLab, sans l'enregistrer. Il n'est active sur aucune machine pour l'instant ;
pour l'utiliser, l'ajouter aux extras de l'hote :

```yaml
extras: [docker, gitlab_runner]
```

L'enregistrement reste manuel, avec un token d'authentification (`glrt-`) cree
dans l'UI GitLab (Settings > CI/CD > Runners > New runner) :

```
sudo gitlab-runner register --url https://gitlab.com --token glrt-xxx
```

### Hostname

Quatre comportements, selon le profil :

| Profil    | OS      | Hostname                                               |
| --------- | ------- | ------------------------------------------------------ |
| `desktop` | mac     | `MacBook-Quentin` (predefini)                          |
| `desktop` | linux   | `Linux-Quentin` (predefini)                            |
| `server`  | --      | **demande** a la premiere configuration, puis persiste |
| `wsl`     | --      | aucun : herite de Windows                              |

Les noms predefinis viennent de `group_vars/desktop.yml` ; `host_vars` les
surcharge pour une machine qui sortirait du moule.

Pour un serveur, la question n'est posee que si le nom n'est pas deja connu :
la reponse est ecrite dans `inventory/host_vars/<hote>.yml`, donc demandee une
seule fois. En run non interactif, passer `hostname_ask=false` : le role echoue
alors nettement au lieu d'attendre une saisie.

### Dotfiles

Geres avec [chezmoi](https://www.chezmoi.io), depot **mono-branche** : les
specificites machine sont des donnees, pas des branches. Le role `dotfiles`
installe chezmoi (Homebrew sur macOS, installeur officiel sur Linux -- aucun
paquet n'existe dans les depots Debian/Ubuntu), puis initialise le depot en
repondant aux deux questions du template sans interaction :

| Donnee chezmoi | Derivee de                   | Valeurs                             |
| -------------- | ---------------------------- | ----------------------------------- |
| `profile`      | l'axe **contexte**           | `perso` -> `perso`, `pro` -> `work` |
| `langs`        | `dotfiles_langs` (host_vars) | java, python, ruby, go, rust        |

Les deux vocabulaires different volontairement : `pro` cote Ansible, `work`
cote dotfiles. Le role fait la traduction.

`langs` est **fige a la premiere initialisation** (`promptMultichoiceOnce`).
Il se declare donc explicitement par machine dans `host_vars`, et se corrige
ensuite en editant `~/.config/chezmoi/chezmoi.toml`.

Les runs suivants sont idempotents : `chezmoi status` est consulte, et
`chezmoi apply` n'est lance que s'il y a quelque chose a appliquer.
`--tags dotfiles-update` tire les derniers commits (jamais joue par defaut).

**Prerequis sur une machine neuve**, a poser a la main avant de lancer Ansible :

| Fichier                        | Pourquoi                                    |
| ------------------------------ | ------------------------------------------- |
| `~/.ssh/id_*` (+ GitHub)       | le depot dotfiles est **prive**             |
| `~/.config/chezmoi/key.txt`    | dechiffre les secrets (`age`), **se recopie** depuis une machine deja configuree -- elle ne se regenere pas |

Le role verifie les deux : absence de cle SSH -> echec immediat avec la marche
a suivre ; absence de cle age -> avertissement, les fichiers chiffres ne sont
simplement pas deployes.

Pour configurer une machine sans les dotfiles en attendant :
`base_skip: [dotfiles]` dans son `host_vars`.

### Distribution inferee

`distro_family` vaut `ansible_facts.os_family` par defaut : `Darwin` sur macOS,
`Debian` sur Ubuntu et Debian. Les roles multi-distributions dispatchent dessus :

```
roles/<role>/tasks/distro/{{ ansible_facts.distribution }}.yml   # Ubuntu.yml : cas particulier
roles/<role>/tasks/distro/{{ distro_family }}.yml                # Debian.yml : cas general
```

Le role `distro_check`, joue en tete de la config de base, valide la famille
detectee. Si elle n'est pas supportee, il la **demande** interactivement, puis
echoue avec un message actionnable si la reponse ne convient pas. En run non
interactif, passer `distro_ask=false` pour qu'il echoue directement.

Ansible ne sait pas detecter WSL (une Ubuntu sous WSL rapporte exactement les
memes facts qu'un vrai serveur Ubuntu) : c'est le **profil**, donc l'inventaire,
qui fait autorite sur ce point -- pas les facts.

## Installation

Sur une machine neuve, un seul script -- macOS, Linux ou WSL :

```sh
curl -fsSL https://raw.githubusercontent.com/quentinpigne/ansible-setup/main/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh <contexte> <profil>
```

| Cas                            | Commande                      |
| ------------------------------ | ----------------------------- |
| Restaurer le Mac perso         | `./bootstrap.sh perso desktop`|
| Nouveau PC perso Linux         | `./bootstrap.sh perso desktop`|
| Serveur perso (Docker, k8s...) | `./bootstrap.sh perso server` |
| Serveur pro                    | `./bootstrap.sh pro server`   |
| Poste pro sous WSL             | `./bootstrap.sh pro wsl`      |

Le script detecte l'OS, installe les prerequis (Command Line Tools + Homebrew
sur macOS ; git + Ansible via apt/dnf/pacman sur Linux), clone le depot,
**declare la machine dans l'inventaire** et lance la configuration.

Les deux fichiers generes (`inventory/10-<hote>.yml` et
`inventory/host_vars/<hote>.yml`) sont a committer : la machine devient alors
reproductible a l'identique.

Prealable sur macOS : autoriser `Full Disk Access` pour le terminal, dans
`Reglages` > `Confidentialite et securite` > `Acces complet au disque`.

### Ensuite

```sh
./apply.sh                 # reappliquer la base sur cette machine
./apply.sh --tags docker   # ajouter un outil
```

### WSL

Le playbook se joue **depuis l'interieur de la distro**. Toute modification de
`/etc/wsl.conf` (hostname, DNS) ne prend effet qu'apres un `wsl --shutdown`
lance depuis Windows.

# Based on

macbook-setup :
* [axinorm/macbook-setup](https://github.com/axinorm/macbook-setup)

osx_defaults :
* [saghul/macOS-setup](https://github.com/saghul/macOS-setup/blob/master/tasks/macos-defaults.yml)
* [ultimateboy/ansible.osx](https://github.com/ultimateboy/ansible.osx/tree/master/roles/ultimateboy.osxdefaults/tasks)
* [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles/blob/master/.macos)

Dock :
* [nickcharlton.net - Automating macOS using Ansible](https://nickcharlton.net/posts/automating-macos-using-ansible.html)

macOS App Store :
* [ayltai/ansible-macos-appstore](https://github.com/ayltai/ansible-macos-appstore)

Global settings with Shell scripts :
* [keith/dotfiles](https://github.com/keith/dotfiles/blob/main/osx/defaults.sh)
* [pawelgrzybek/dotfiles](https://github.com/pawelgrzybek/dotfiles/blob/master/setup-macos.sh)
* [kdeldycke/dotfiles](https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh)
