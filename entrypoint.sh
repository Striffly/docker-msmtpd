#!/bin/sh
# shellcheck shell=busybox
# Writes the msmtp configuration from the SMTP_* variables, then runs msmtpd: an
# SMTP relay without authentication on LISTEN_PORT, which sends every mail it
# receives on through SMTP_HOST with the account below.
set -eu

conf=/run/msmtpd/msmtprc
secret=/run/msmtpd/password
umask 077

die() { echo "msmtpd: $*" >&2; exit 1; }

# SMTP_USER and SMTP_PASSWORD may come from files instead (Docker secrets).
if [ -n "${SMTP_USER_FILE:-}" ]; then
  [ -z "${SMTP_USER:-}" ] || die "SMTP_USER and SMTP_USER_FILE are exclusive"
  SMTP_USER=$(cat "$SMTP_USER_FILE")
fi
if [ -n "${SMTP_PASSWORD_FILE:-}" ]; then
  [ -z "${SMTP_PASSWORD:-}" ] || die "SMTP_PASSWORD and SMTP_PASSWORD_FILE are exclusive"
  SMTP_PASSWORD=$(cat "$SMTP_PASSWORD_FILE")
fi
[ -n "${SMTP_HOST:-}" ] || die "SMTP_HOST must be defined"

# SMTP_SECURITY takes vaultwarden's values, so one setting can serve both:
# starttls, force_tls or off. SMTP_TLS and SMTP_STARTTLS win when set.
case "${SMTP_SECURITY:-}" in
  starttls)  tls=on;  starttls=on ;;
  force_tls) tls=on;  starttls=off ;;
  off)       tls=off; starttls=off ;;
  "")        tls="";  starttls="" ;;
  *) die "SMTP_SECURITY must be starttls, force_tls or off, not \"$SMTP_SECURITY\"" ;;
esac
tls=${SMTP_TLS:-$tls}
starttls=${SMTP_STARTTLS:-$starttls}
# A user means authentication, unless SMTP_AUTH says otherwise.
auth=${SMTP_AUTH:-}
[ -n "$auth" ] || [ -z "${SMTP_USER:-}" ] || auth=on

# option <keyword> <value>: one configuration line, only when the value is set.
# msmtp reads a double-quoted argument literally, except for \" and \\.
option() {
  [ -n "$2" ] || return 0
  v=${2//\\/\\\\}
  printf '%s "%s"\n' "$1" "${v//\"/\\\"}"
}

{
  echo "account default"
  echo "syslog off"
  echo "logfile -"
  option host "$SMTP_HOST"
  option port "${SMTP_PORT:-}"
  option tls "$tls"
  option tls_starttls "$starttls"
  option tls_certcheck "${SMTP_TLS_CHECKCERT:-}"
  option auth "$auth"
  option user "${SMTP_USER:-}"
  option domain "${SMTP_DOMAIN:-}"
  option from "${SMTP_FROM:-}"
  option from_full_name "${SMTP_FROM_FULL_NAME:-}"
  option allow_from_override "${SMTP_ALLOW_FROM_OVERRIDE:-}"
  option set_from_header "${SMTP_SET_FROM_HEADER:-}"
  option set_date_header "${SMTP_SET_DATE_HEADER:-}"
  option remove_bcc_headers "${SMTP_REMOVE_BCC_HEADERS:-}"
  option undisclosed_recipients "${SMTP_UNDISCLOSED_RECIPIENTS:-}"
  option dsn_notify "${SMTP_DSN_NOTIFY:-}"
  option dsn_return "${SMTP_DSN_RETURN:-}"
  # The password stays in its own file, read back byte for byte: inside the
  # configuration it would have to be escaped.
  if [ -n "${SMTP_PASSWORD:-}" ]; then
    printf '%s' "$SMTP_PASSWORD" > "$secret"
    echo "passwordeval \"cat $secret\""
  fi
} > "$conf"
unset SMTP_USER SMTP_PASSWORD SMTP_USER_FILE SMTP_PASSWORD_FILE

echo "msmtpd: relaying port $LISTEN_PORT to $SMTP_HOST${SMTP_PORT:+:$SMTP_PORT}"
exec msmtpd --interface=0.0.0.0 --port="$LISTEN_PORT" --log=/dev/stderr \
  --command="msmtp -C $conf -f %F --"
