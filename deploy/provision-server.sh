#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# provision-server.sh — configurazione del server al PRIMO deploy (idempotente)
#
# Gira SUL VPS (Debian/Ubuntu). Alla prima esecuzione:
#   1. installa Nginx e Certbot se mancano;
#   2. crea il virtual server Nginx per il dominio;
#   3. richiede il certificato SSL Let's Encrypt e attiva l'HTTPS + redirect.
# Alle esecuzioni successive non tocca nulla di configurato: si limita a
# ricaricare Nginx (i contenuti del sito arrivano via rsync, a parte).
#
# Variabili d'ambiente:
#   DOMAIN        (obbligatoria)  es. anticatrattoriacirio.it
#   WEBROOT       (obbligatoria)  cartella servita da Nginx (= target rsync)
#   EMAIL         (consigliata)   email per Let's Encrypt; se vuota, salta SSL
#   INCLUDE_WWW   (opzionale)     "true"/"false" — includi anche www.DOMAIN (default true)
#   TEMPLATE      (opzionale)     percorso del template nginx (default: accanto a questo script)
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

: "${DOMAIN:?Variabile DOMAIN mancante}"
: "${WEBROOT:?Variabile WEBROOT mancante}"
EMAIL="${EMAIL:-}"
INCLUDE_WWW="${INCLUDE_WWW:-true}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE:-$SCRIPT_DIR/nginx-site.conf.template}"

if [ ! -f "$TEMPLATE" ]; then
  echo "[provision] ERRORE: template Nginx non trovato: $TEMPLATE" >&2
  exit 1
fi

# sudo solo se non siamo già root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

log(){ echo "[provision] $*"; }

# 1) Dipendenze ------------------------------------------------------------
need_apt_update=true
apt_update_once(){ if $need_apt_update; then $SUDO apt-get update -y; need_apt_update=false; fi; }

if ! command -v nginx >/dev/null 2>&1; then
  log "Installo Nginx…"
  apt_update_once
  $SUDO apt-get install -y nginx
fi
if ! command -v certbot >/dev/null 2>&1; then
  log "Installo Certbot (plugin Nginx)…"
  apt_update_once
  $SUDO apt-get install -y certbot python3-certbot-nginx
fi

# 2) Webroot ---------------------------------------------------------------
$SUDO mkdir -p "$WEBROOT"

# server_name: dominio (+ www se richiesto e non è già un www.)
# Aggiungi "www." SOLO a un dominio apex (un solo punto, es. esempio.it) e
# mai a un sottodominio (es. prenotazioni.esempio.it): il "www." di un
# sottodominio non esiste nel DNS e farebbe fallire l'intera richiesta certbot.
WWW_OK=false
if [ "$INCLUDE_WWW" = "true" ] && [[ "$DOMAIN" != www.* ]]; then
  dots="${DOMAIN//[^.]/}"
  if [ "${#dots}" -eq 1 ]; then WWW_OK=true; fi
fi
SERVER_NAMES="$DOMAIN"
if $WWW_OK; then SERVER_NAMES="$DOMAIN www.$DOMAIN"; fi

SITE_AVAILABLE="/etc/nginx/sites-available/$DOMAIN.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/$DOMAIN.conf"

# 3) Virtual server (solo se non esiste già) -------------------------------
if [ ! -f "$SITE_AVAILABLE" ]; then
  log "Primo deploy: creo il virtual server Nginx per '$SERVER_NAMES'"
  tmp="$(mktemp)"
  sed -e "s|__SERVER_NAMES__|$SERVER_NAMES|g" \
      -e "s|__WEBROOT__|$WEBROOT|g" \
      "$TEMPLATE" > "$tmp"
  $SUDO cp "$tmp" "$SITE_AVAILABLE"
  rm -f "$tmp"
  $SUDO ln -sf "$SITE_AVAILABLE" "$SITE_ENABLED"
  # Disattiva il default di Nginx per non intercettare il dominio
  if [ -e /etc/nginx/sites-enabled/default ]; then
    $SUDO rm -f /etc/nginx/sites-enabled/default
  fi
else
  log "Virtual server già presente ($SITE_AVAILABLE) — nessuna modifica alla config"
fi

# 4) Test + reload ---------------------------------------------------------
log "Verifico la configurazione Nginx…"
$SUDO nginx -t
$SUDO systemctl reload nginx

# 5) Certificato SSL (solo al primo deploy) --------------------------------
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  log "Certificato SSL già presente per $DOMAIN (rinnovo automatico via timer certbot)"
else
  if [ -z "$EMAIL" ]; then
    log "ATTENZIONE: EMAIL non impostata → salto la richiesta SSL. Il sito resta in HTTP."
  else
    log "Richiedo il certificato SSL Let's Encrypt per '$SERVER_NAMES'…"
    # --redirect: certbot aggiunge il blocco 443 e forza HTTPS.
    certbot_run(){
      $SUDO certbot --nginx "$@" --non-interactive --agree-tos -m "$EMAIL" --redirect
    }
    ok=false
    if $WWW_OK; then
      if certbot_run -d "$DOMAIN" -d "www.$DOMAIN"; then
        ok=true
      else
        # www potrebbe non risolvere nel DNS: ritenta col solo dominio,
        # così un certificato valido viene comunque emesso.
        log "certbot con www ha fallito → ritento senza www…"
        certbot_run -d "$DOMAIN" && ok=true
      fi
    else
      certbot_run -d "$DOMAIN" && ok=true
    fi
    if $ok; then
      $SUDO systemctl reload nginx
      log "SSL attivo."
    else
      log "ATTENZIONE: certbot ha fallito. Verifica che '$DOMAIN' punti (record A) all'IP del VPS e che le porte 80/443 siano aperte, poi rilancia il deploy."
    fi
  fi
fi

log "Fatto → http(s)://$DOMAIN"
