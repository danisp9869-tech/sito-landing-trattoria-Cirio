#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# deploy.sh — deploy MANUALE della landing su un VPS Nginx, dal tuo computer.
#
# Fa le stesse cose del workflow GitHub Actions:
#   1. copia i file del sito sul server via rsync;
#   2. crea (al primo giro) il virtual server Nginx + certificato SSL.
#
# Uso:
#   1. copia deploy/.env.example in deploy/.env e compila i valori;
#   2. lancia:  bash deploy/deploy.sh
#
# In alternativa al file .env puoi passare le variabili a mano:
#   VPS_HOST=1.2.3.4 VPS_USER=deploy VPS_TARGET_DIR=/var/www/cirio \
#   VPS_DOMAIN=esempio.it VPS_EMAIL=info@esempio.it bash deploy/deploy.sh
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carica deploy/.env se presente
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; . "$SCRIPT_DIR/.env"; set +a
fi

: "${VPS_HOST:?Imposta VPS_HOST (IP o hostname del server)}"
: "${VPS_USER:?Imposta VPS_USER (utente SSH sul server)}"
: "${VPS_TARGET_DIR:?Imposta VPS_TARGET_DIR (cartella web, es. /var/www/cirio)}"
: "${VPS_DOMAIN:?Imposta VPS_DOMAIN (es. anticatrattoriacirio.it)}"

PORT="${VPS_PORT:-22}"
SSH_KEY="${VPS_SSH_KEY_FILE:-$HOME/.ssh/id_rsa}"
EMAIL="${VPS_EMAIL:-}"
INCLUDE_WWW="${VPS_INCLUDE_WWW:-true}"

if [ ! -f "$SSH_KEY" ]; then
  echo "ERRORE: chiave SSH non trovata: $SSH_KEY (imposta VPS_SSH_KEY_FILE)" >&2
  exit 1
fi

SSH_BASE=(ssh -i "$SSH_KEY" -p "$PORT")

echo "==> [1/3] rsync dei contenuti su $VPS_HOST:$VPS_TARGET_DIR"
rsync -avz --delete \
  -e "ssh -i $SSH_KEY -p $PORT" \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.gitattributes' \
  --exclude='README.md' \
  --exclude='deploy' \
  "$REPO_DIR/" "$VPS_USER@$VPS_HOST:$VPS_TARGET_DIR/"

echo "==> [2/3] copio lo script di provisioning sul server"
scp -i "$SSH_KEY" -P "$PORT" \
  "$SCRIPT_DIR/provision-server.sh" \
  "$SCRIPT_DIR/nginx-site.conf.template" \
  "$VPS_USER@$VPS_HOST:/tmp/"

echo "==> [3/3] provisioning Nginx + SSL (idempotente)"
"${SSH_BASE[@]}" "$VPS_USER@$VPS_HOST" \
  "DOMAIN='$VPS_DOMAIN' EMAIL='$EMAIL' WEBROOT='$VPS_TARGET_DIR' INCLUDE_WWW='$INCLUDE_WWW' TEMPLATE=/tmp/nginx-site.conf.template bash /tmp/provision-server.sh"

echo ""
echo "✅ Deploy completato → https://$VPS_DOMAIN"
