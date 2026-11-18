#!/bin/sh
set -u

: "${CF_TOKEN:?CF_TOKEN is required}"
: "${DDNS_ZONE:=wannaknow.uk}"
: "${DDNS_HOSTS:=wannaknow.win:all help.wannaknow.win:4 remote.wannaknow.uk:all}"
: "${ACME_DOMAINS:=-d wannaknow.uk -d *.wannaknow.uk -d wannaknow.win -d *.wannaknow.win}"
: "${ACME_MAIN:=wannaknow.uk}"
: "${INTERVAL:=300}"

ACME_HOME=/acme.sh
ACME="$ACME_HOME/acme.sh"
CERT_DIR=/certs

export CF_Token="$CF_TOKEN"
[ -n "${CF_ACCOUNT_ID:-}" ] && export CF_Account_ID="$CF_ACCOUNT_ID"
[ -n "${CF_ZONE_ID:-}" ] && export CF_Zone_ID="$CF_ZONE_ID"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

init_acme() {
  if [ ! -x "$ACME" ]; then
    log "acme: initializing from pre-bundled /opt/acme.sh"
    cp -r /opt/acme.sh/* "$ACME_HOME"/
    chmod +x "$ACME"
  fi
  if [ ! -d "$ACME_HOME/$ACME_MAIN" ]; then
    log "acme: issuing for $ACME_DOMAINS"
    $ACME --set-default-ca --server letsencrypt --home "$ACME_HOME" || log "acme: set-ca failed (continuing)"
    # shellcheck disable=SC2086
    $ACME --issue --dns dns_cf $ACME_DOMAINS --home "$ACME_HOME" || { log "acme: issue FAILED"; return 1; }
    install_cert
  fi
}

install_cert() {
  log "acme: installing cert to $CERT_DIR"
  $ACME --install-cert -d "$ACME_MAIN" \
    --key-file       "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --ca-file        "$CERT_DIR/chain.pem" \
    --reloadcmd      "touch $CERT_DIR/.reload" \
    --home "$ACME_HOME" || log "acme: install-cert failed (continuing)"
}

do_ddns() {
  for spec in $DDNS_HOSTS; do
    h=${spec%:*}
    t=${spec##*:}
    [ "$t" = "$spec" ] && t=all
    case $t in
      4|6|all) : ;;
      *) log "ddns: $h has bad type '$t', skipping"; continue ;;
    esac
    z=$(printf '%s' "$h" | awk -F. '{print $(NF-1)"."$NF}')
    [ -n "$z" ] || z="$DDNS_ZONE"
    log "ddns: $h (zone $z, type $t)"
    /usr/local/bin/cf-ddns.sh -k "$CF_TOKEN" -h "$h" -z "$z" -t "$t" \
      || log "ddns: $h FAILED (continuing)"
  done
}

run_once() {
  do_ddns || true
  log "acme: cron"
  $ACME --cron --home "$ACME_HOME" || log "acme: cron FAILED (continuing)"
  [ -f "$CERT_DIR/fullchain.pem" ] || install_cert || true
}

init_acme || log "init failed, will retry in loop"
while true; do
  run_once
  sleep "$INTERVAL"
done
