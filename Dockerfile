# syntax=docker/dockerfile:1

# The current Alpine 3 branch. The daily rebuild (rebuild-on-updates.yml) picks
# up its security fixes and, when Alpine releases a new branch, moves to it on
# its own: a branch never has to be bumped by hand before it leaves support.
# Every build must pass tests/run.sh before it is published, and hosts can hold
# a new image back for a while before installing it.
FROM alpine:3

# msmtp and msmtpd come from Alpine's signed packages instead of a source
# tarball fetched without a checksum, so a fixed msmtp, OpenSSL or libc arrives
# with the next rebuild. No init system: msmtpd is the only process.
RUN apk add --no-cache ca-certificates msmtp tzdata \
  && addgroup -g 1500 msmtpd \
  && adduser -D -H -u 1500 -G msmtpd -s /sbin/nologin msmtpd \
  && install -d -o msmtpd -g msmtpd -m 0700 /run/msmtpd

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV LISTEN_PORT=2500 \
  TZ=UTC

# Never root: the relay only needs its own configuration directory.
USER 1500:1500
EXPOSE 2500

# A real SMTP greeting from the relay, not just an open port.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD msmtp -C /dev/null --host=127.0.0.1 --port="$LISTEN_PORT" --tls=off --auth=off --serverinfo > /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
