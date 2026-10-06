#!/usr/bin/env bash
#
# Applique la configuration a une machine.
#
#   ./apply.sh                    cette machine
#   ./apply.sh --tags docker      cette machine, un outil en plus
#   ./apply.sh ubuntu01           une autre machine (par nom d'hote ou de groupe)
#   ./apply.sh perso --tags dns   un groupe, avec des tags
#
# La cible est toujours explicite : sans cible, le playbook viserait les trois
# machines a la fois, et un hote en connexion locale designe la machine
# courante quel que soit son nom -- ce qui appliquerait la mauvaise config.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

die() { echo "[ERREUR] $*" >&2; exit 1; }

# La cible est le premier argument s'il ne commence pas par un tiret.
TARGET=""
if [[ $# -gt 0 && "$1" != -* ]]; then
  TARGET="$1"; shift
fi

# Sans cible explicite : l'hote en connexion locale dont l'OS declare
# correspond a celui de la machine. C'est le meme critere que le garde-fou du
# role distro_check.
if [[ -z "$TARGET" ]]; then
  case "$(uname -s)" in
    Darwin) HOST_OS="mac" ;;
    Linux)  HOST_OS="linux" ;;
    *)      die "OS non reconnu : $(uname -s)" ;;
  esac

  # `mapfile` demanderait bash 4 : macOS livre encore la 3.2.
  CANDIDATES=$(
    ansible-inventory --list 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
want = sys.argv[1]
for name, hostvars in data.get("_meta", {}).get("hostvars", {}).items():
    if hostvars.get("ansible_connection") == "local" and hostvars.get("os") == want:
        print(name)
' "$HOST_OS"
  )
  COUNT=$(printf '%s' "$CANDIDATES" | grep -c . || true)

  case "$COUNT" in
    1) TARGET="$CANDIDATES"
       echo "[INFO] Machine courante : $TARGET ($HOST_OS)" ;;
    0) die "aucun hote local declare pour cet OS ($HOST_OS).
       Declarer la machine dans l'inventaire, ou passer la cible en argument :
       ./apply.sh <hote>" ;;
    *) die "plusieurs hotes locaux possibles : $(echo $CANDIDATES).
       Preciser lequel : ./apply.sh <hote>" ;;
  esac
fi

# Verifie que la cible existe avant de lancer quoi que ce soit.
# `ansible --list-hosts` sort en 0 meme sur un motif inconnu : on compte les
# hotes retournes plutot que de se fier au code de retour.
MATCHED=$(ansible "$TARGET" --list-hosts 2>/dev/null | tail -n +2 | grep -c . || true)
if [[ "$MATCHED" -eq 0 ]]; then
  die "cible inconnue : '$TARGET'. Hotes et groupes disponibles :
$(ansible-inventory --graph 2>/dev/null | sed 's/^/       /')"
fi

# --ask-become-pass seulement si un terminal peut repondre : sinon le script
# se bloquerait sur la demande de mot de passe (CI, run automatise).
BECOME=()
if [[ -t 0 ]]; then BECOME=(--ask-become-pass); fi

echo "[INFO] ansible-playbook site.yml --limit $TARGET $*"
exec ansible-playbook site.yml --limit "$TARGET" "${BECOME[@]+"${BECOME[@]}"}" "$@"
