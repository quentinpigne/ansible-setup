#!/usr/bin/env bash
#
# Bootstrap d'une machine neuve, macOS ou Linux (WSL inclus).
#
#   ./bootstrap.sh <contexte> <profil>
#
#   contexte : perso | pro
#   profil   : desktop | server | wsl
#
# L'OS est detecte. La machine est declaree dans l'inventaire, puis configuree.
# Exemples :
#   ./bootstrap.sh perso desktop     Mac ou PC perso
#   ./bootstrap.sh perso server      serveur perso
#   ./bootstrap.sh pro wsl           poste pro sous WSL
#   ./bootstrap.sh pro server        serveur pro

set -euo pipefail

REPO_URL="https://github.com/quentinpigne/ansible-setup"
REPO_DIR="${ANSIBLE_SETUP_DIR:-$HOME/Workspace/ansible-setup}"

die() { echo "[ERREUR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

# ---------------------------------------------------------------- arguments
CONTEXT="${1:-}"
PROFILE="${2:-}"
case "$CONTEXT" in perso|pro) ;; *) die "contexte invalide : '${CONTEXT:-<vide>}' (perso | pro)";; esac
case "$PROFILE" in desktop|server|wsl) ;; *) die "profil invalide : '${PROFILE:-<vide>}' (desktop | server | wsl)";; esac

# ---------------------------------------------------------------- detection
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS="mac"
else
  OS="linux"
  # WSL n'est pas detectable par les facts Ansible : on le voit ici, mais
  # c'est le profil choisi par l'utilisateur qui fait foi.
  if grep -qi microsoft /proc/version 2>/dev/null && [[ "$PROFILE" != "wsl" ]]; then
    info "WSL detecte alors que le profil demande est '$PROFILE'."
  fi
fi
info "Machine : contexte=$CONTEXT profil=$PROFILE os=$OS"

# ------------------------------------------------------------ prerequis mac
if [[ "$OS" == "mac" ]]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Installation des Command Line Tools"
    xcode-select --install
    # xcode-select --install rend la main immediatement : l'install est asynchrone.
    info "Attente de la fin de l'installation..."
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi

  if ! command -v brew >/dev/null 2>&1; then
    info "Installation de Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # /opt/homebrew sur Apple Silicon, /usr/local sur Intel
  for prefix in /opt/homebrew /usr/local; do
    if [[ -x "$prefix/bin/brew" ]]; then eval "$("$prefix/bin/brew" shellenv)"; break; fi
  done

  command -v git >/dev/null 2>&1 || brew install git
  command -v ansible-playbook >/dev/null 2>&1 || { info "Installation d'Ansible"; brew install ansible; }

# ---------------------------------------------------------- prerequis linux
else
  if command -v apt-get >/dev/null 2>&1; then
    INSTALL="sudo apt-get install -y"
    info "Mise a jour de l'index APT"
    sudo apt-get update -qq
  elif command -v dnf >/dev/null 2>&1; then
    INSTALL="sudo dnf install -y"
  elif command -v pacman >/dev/null 2>&1; then
    INSTALL="sudo pacman -S --noconfirm"
  else
    die "gestionnaire de paquets non reconnu : installer git et ansible a la main, puis relancer."
  fi

  command -v git >/dev/null 2>&1 || { info "Installation de git"; $INSTALL git; }
  command -v ansible-playbook >/dev/null 2>&1 || { info "Installation d'Ansible"; $INSTALL ansible; }
fi

# -------------------------------------------------------------------- depot
if [[ ! -d "$REPO_DIR" ]]; then
  info "Clonage du depot dans $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"

info "Installation des collections Ansible"
ansible-galaxy collection install -r requirements.yml

# ------------------------------------------------- declaration de la machine
# Ecrit dans un fichier d'inventaire dedie : l'inventaire est un repertoire,
# Ansible fusionne tous les fichiers qu'il contient.
HOST="$(hostname -s 2>/dev/null || hostname)"
LOCAL_INV="inventory/10-${HOST}.yml"

if [[ ! -f "$LOCAL_INV" ]]; then
  info "Declaration de '$HOST' dans $LOCAL_INV"
  cat > "$LOCAL_INV" <<EOF
---
# Genere par bootstrap.sh. A committer pour que la machine soit reproductible.
all:
  children:
    ${CONTEXT}:
      hosts:
        ${HOST}:
    ${PROFILE}:
      hosts:
        ${HOST}:
    ${OS}:
      hosts:
        ${HOST}:
          ansible_connection: local
EOF
fi

if [[ ! -f "inventory/host_vars/${HOST}.yml" ]]; then
  cat > "inventory/host_vars/${HOST}.yml" <<EOF
---
# Le hostname n'est pas fige ici : un poste de travail le tient de
# group_vars/desktop.yml, un serveur se le voit demander a la configuration
# (la reponse est persistee dans ce fichier), WSL n'en a pas.

# Installations optionnelles. Catalogue : extras_available (group_vars/all.yml)
# Les langages ne sont pas installes par defaut : --tags java, --tags rust, ...
extras: []
EOF
  info "Cree inventory/host_vars/${HOST}.yml -- y declarer les extras voulus."
fi

# ------------------------------------------------------------------ execution
info "Configuration de la machine"
./apply.sh "$HOST" "${@:3}"

info "Termine. Penser a committer $LOCAL_INV et inventory/host_vars/${HOST}.yml"
