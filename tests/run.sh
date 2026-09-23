#!/bin/bash
# End-to-end test of the image: a client hands mail to the relay, which sends it
# on to an SMTP server (mailpit) that requires STARTTLS and a login. Also: a
# password with quotes, backslashes, $ and a backquote, credentials from files, a wrong
# password refused, the healthcheck, and the process never running as root.
#   bash tests/run.sh [image]      (builds msmtpd:test when no image is given)
# Needs Docker and access to Docker Hub for axllent/mailpit. Removes only what
# it creates: containers and a network whose names start with "msmtpd-test".
set -u
IMAGE="${1:-}"
if [ -z "${IMAGE}" ]; then
    IMAGE=msmtpd:test
    docker build -q -t "${IMAGE}" "$(dirname "$0")/.." > /dev/null || exit 2
fi
NET=msmtpd-test; SMTP=msmtpd-test-smtp; RELAY=msmtpd-test-relay
# Quotes, a backslash, $ and a backquote: whatever a shell or the msmtp
# configuration would interpret. No space: mailpit's login file splits on it.
# shellcheck disable=SC2016 # literal on purpose
PASSWORD='p"a\s$s`wo\"rd'
D=$(mktemp -d); fail=0
ok() { # ok <title> <expected> <got>
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
    else printf '  FAIL %s\n       expected: "%s"\n       got:      "%s"\n' "$1" "$2" "$3"; fail=1; fi
}
cleanup() {
    docker rm -f "${SMTP}" "${RELAY}" > /dev/null 2>&1
    docker network rm "${NET}" > /dev/null 2>&1
}
trap 'cleanup; rm -rf "${D}"' EXIT
cleanup

docker network create "${NET}" > /dev/null || exit 2
# STARTTLS required, with a self-signed certificate, and a login. mailpit reads
# its accepted logins from a file, one "user:password" per line.
printf 'relay:%s\n' "${PASSWORD}" > "${D}/auth"
chmod 644 "${D}/auth"
docker run -d --name "${SMTP}" --network "${NET}" -v "${D}/auth:/auth:ro" \
    -e MP_SMTP_TLS_CERT=sans:"${SMTP}" -e MP_SMTP_TLS_KEY=sans:"${SMTP}" -e MP_SMTP_REQUIRE_STARTTLS=true \
    -e MP_SMTP_AUTH_FILE=/auth axllent/mailpit > /dev/null || exit 2
mails() { docker exec "${SMTP}" wget -qO- http://127.0.0.1:8025/api/v1/messages | sed -n 's/.*"total":\([0-9]*\).*/\1/p'; }
until [ -n "$(mails)" ]; do sleep 1; done

# relay <extra docker run options…>: a relay to the test server, running and ready.
relay() {
    docker rm -f "${RELAY}" > /dev/null 2>&1
    docker run -d --name "${RELAY}" --network "${NET}" -e SMTP_HOST="${SMTP}" -e SMTP_PORT=1025 \
        -e SMTP_SECURITY=starttls -e SMTP_TLS_CHECKCERT=off -e SMTP_FROM=vault@example.com "$@" "${IMAGE}" > /dev/null
    for _ in $(seq 1 30); do
        docker exec "${RELAY}" msmtp -C /dev/null --host=127.0.0.1 --port=2500 --tls=off --auth=off --serverinfo \
            > /dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}
# send <subject>: a client hands a message to the relay, without a login.
send() {
    printf 'From: vault@example.com\nTo: admin@example.com\nSubject: %s\n\nbody\n' "$1" \
        | docker run --rm -i --network "${NET}" --entrypoint msmtp "${IMAGE}" -C /dev/null \
              --host="${RELAY}" --port=2500 --tls=off --auth=off --from=vault@example.com admin@example.com
}

echo "== Relay with a password full of quotes, backslashes, \$ and a backquote =="
relay -e SMTP_USER=relay -e SMTP_PASSWORD="${PASSWORD}"
ok "relay ready" 0 "$?"
before=$(mails); send "via the relay" > /dev/null 2>&1
ok "mail accepted and delivered over STARTTLS with the login" "$(( before + 1 ))" "$(mails)"
ok "runs as uid 1500" 1500 "$(docker exec "${RELAY}" id -u)"
ok "configuration private" 600 "$(docker exec "${RELAY}" stat -c %a /run/msmtpd/msmtprc)"
ok "password not in the configuration" 0 "$(docker exec "${RELAY}" grep -cF "${PASSWORD}" /run/msmtpd/msmtprc)"
ok "password kept byte for byte" "${PASSWORD}" "$(docker exec "${RELAY}" cat /run/msmtpd/password)"
health=""
for _ in $(seq 1 20); do
    health=$(docker inspect -f '{{.State.Health.Status}}' "${RELAY}" 2> /dev/null)
    [ "${health}" = healthy ] && break; sleep 2
done
ok "healthcheck healthy" healthy "${health}"

echo "== Credentials from files (Docker secrets) =="
printf 'relay' > "${D}/user"; printf '%s' "${PASSWORD}" > "${D}/password"; chmod 644 "${D}/user" "${D}/password"
relay -v "${D}/user:/run/secrets/user:ro" -v "${D}/password:/run/secrets/password:ro" \
    -e SMTP_USER_FILE=/run/secrets/user -e SMTP_PASSWORD_FILE=/run/secrets/password
before=$(mails); send "from secrets" > /dev/null 2>&1
ok "mail delivered" "$(( before + 1 ))" "$(mails)"

echo "== Wrong password =="
relay -e SMTP_USER=relay -e SMTP_PASSWORD=wrong
before=$(mails); send "wrong password" > /dev/null 2>&1; rc=$?
ok "the client is told it failed" 1 "$(( rc != 0 ))"
ok "nothing delivered" "${before}" "$(mails)"

echo "== Misconfiguration stops the container =="
docker rm -f "${RELAY}" > /dev/null 2>&1
out=$(docker run --rm "${IMAGE}" 2>&1); rc=$?
ok "no SMTP_HOST: exits" 1 "$(( rc != 0 ))"
ok "  and says why" yes "$(grep -q "SMTP_HOST must be defined" <<< "${out}" && echo yes || echo no)"
out=$(docker run --rm -e SMTP_HOST=x -e SMTP_SECURITY=tls "${IMAGE}" 2>&1); rc=$?
ok "unknown SMTP_SECURITY: exits" 1 "$(( rc != 0 ))"

[ "${fail}" = 0 ] && echo "ALL CASES PASS" || echo "SOME CASES FAIL"
exit "${fail}"
