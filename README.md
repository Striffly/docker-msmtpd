# msmtpd SMTP relay

A small SMTP relay built on [msmtpd](https://marlam.de/msmtp/). Containers hand their mail to it, without credentials, on port 2500. It sends the mail on through one real SMTP account, so only this container holds the SMTP password.

This is a fork of [crazy-max/docker-msmtpd](https://github.com/crazy-max/docker-msmtpd) (MIT), rebuilt to be maintained the way the [bwgc images](https://github.com/Striffly/bwgc_backup) are:

- **msmtp comes from Alpine's signed packages**, not from a source tarball downloaded without a checksum. A fixed msmtp, OpenSSL or musl reaches the image through the next rebuild.
- **Rebuilt every day when needed**: whenever the `alpine` base or any installed package falls behind (`rebuild-on-updates.yml`). An issue is opened before the pinned Alpine branch leaves support (`check-base-image-support.yml`).
- **Tested before every publish**: `tests/run.sh` relays mail end to end through STARTTLS and a login, reads credentials from files, and must see a wrong password refused.
- **Scanned and signed**: Trivy, then cosign keyless signing.
- **Tagged per build**: `master`, plus `master-YYYYMMDD-HHmmss`, which never moves.
- **Simpler at runtime**: no s6 init and never root. It runs as uid 1500 and writes only `/run/msmtpd`. The password is kept byte for byte in its own private file, so quotes, backslashes, `$` or spaces in it need no escaping.

`PUID` and `PGID` are gone: the relay writes no file outside the container. The other variables are unchanged, and `SMTP_SECURITY` is new.

## Image

`ghcr.io/striffly/docker-msmtpd:master`, or a dated tag to pin one build. Only `linux/amd64` is built.

## Environment variables

* `TZ`: Timezone (default `UTC`)
* `LISTEN_PORT`: Container listen port for msmtpd, useful with host, macvlan, or ipvlan networking (default `2500`)
* `SMTP_HOST`: SMTP relay server to send the mail to. **required**
* `SMTP_PORT`: Port that the SMTP relay server listens on. Default `25` or `465` if TLS.
* `SMTP_SECURITY`: `starttls`, `force_tls` or `off`, as vaultwarden reads them: sets `SMTP_TLS` and `SMTP_STARTTLS` together. Either of those, when set, wins.
* `SMTP_TLS`: Enable or disable TLS (also known as SSL) for secured connections (`on` or `off`).
* `SMTP_STARTTLS`: Start TLS from within the session (`on`, default), or tunnel the session through TLS (`off`).
* `SMTP_TLS_CHECKCERT`: Enable or disable checks of the server certificate (`on` or `off`). They are enabled by default.
* `SMTP_AUTH`: Enable or disable authentication and optionally [choose a method](https://marlam.de/msmtp/msmtp.html#Authentication-commands) to use. The argument `on` chooses a method automatically. Defaults to `on` when `SMTP_USER` is set.
* `SMTP_USER`: Set the username for authentication. 
* `SMTP_PASSWORD`: Set the password for authentication. 
* `SMTP_DOMAIN`: Argument of the `SMTP EHLO` command (default `localhost`)
* `SMTP_FROM`: Set the envelope-from address. Supported substitution patterns can be found [here](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode).
* `SMTP_FROM_FULL_NAME`: Set the full name to use in the From header when msmtp adds one.
* `SMTP_ALLOW_FROM_OVERRIDE`: Allow configured envelope-from address to be overriden by actual SMTP MAIL FROM . Can be [`on` or `off`](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode) (default `on`)
* `SMTP_SET_FROM_HEADER`: When to set a From header. Can be [`auto`, `on` or `off`](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode) (default `auto`)
* `SMTP_SET_DATE_HEADER`: When to set a Date header. Can be [`auto` or `off`](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode) (default `auto`)
* `SMTP_REMOVE_BCC_HEADERS`: Controls whether to remove Bcc headers. Can be [`on` or `off`](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode) (default `on`)
* `SMTP_UNDISCLOSED_RECIPIENTS`: When set, the original To, Cc, and Bcc headers of the mail are removed and a single new header line `To: undisclosed-recipients:;` is added. Can be [`on` or `off`](https://marlam.de/msmtp/msmtp.html#Commands-specific-to-sendmail-mode) (default `off`)
* `SMTP_DSN_NOTIFY`: Set the condition(s) under which the mail system should send DSN (Delivery Status Notification) messages as comma separated values. Available values are [`off`, `never`, `failure`, `delay` and `success`](https://marlam.de/msmtp/msmtp.html#index-dsn_005fnotify) (default `off`)
* `SMTP_DSN_RETURN`: Controls how much of a mail should be returned in DSN (Delivery Status Notification) messages. Can be [`headers`, `full` or `off`](https://marlam.de/msmtp/msmtp.html#index-dsn_005freturn) (default `off`)

> [!NOTE]
> `SMTP_USER_FILE` and `SMTP_PASSWORD_FILE` can be used to fill in the value
> from a file, especially for Docker's secrets feature.

More info: https://marlam.de/msmtp/msmtp.html

## Ports

* `2500`: SMTP relay port, configurable through `LISTEN_PORT`. The relay asks for no login, so keep it on an internal network: never publish this port.

## Usage

See [examples/compose](examples/compose/compose.yml). A client sends to host `msmtpd`, port `2500`, without TLS or authentication.

## Tests

```sh
bash tests/run.sh            # builds msmtpd:test, then tests it
bash tests/run.sh <image>    # tests an existing image
```

It needs Docker and `axllent/mailpit`, and removes only the containers and network it creates.

## License

MIT. See `LICENSE`, originally by CrazyMax.
