# syntax=docker/dockerfile:1

# Pinned to an Alpine branch rather than :latest. The branch's security fixes
# reach the image through the daily rebuild (rebuild-on-updates.yml); moving to
# the next branch is a deliberate change, which check-base-image-support.yml
# raises before the pinned one leaves support.
FROM alpine:3.24

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
