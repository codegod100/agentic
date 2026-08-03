# Experimental password manager + OpenBao

**Scaffold.** Not a production password manager.

Inspired by [openbao-passkeys](https://github.com/codegod100/openbao-passkeys): passwords and software passkeys live in OpenBao KV v2.

## What it is

- `OpenBaoStore` — sync libcurl client for OpenBao KV v2
- CredMan hooks: `password` create / get / store + passkeys persisted to the same store
- Form autofill into empty username/password `<input>`s + silent save on submit
- Qt **Edit → Password Manager…** dialog to list / delete / manually add password entries

## Configuration

| Env | Default | Purpose |
|-----|---------|---------|
| `BAO_ADDR` / `OPENBAO_ADDR` / `VAULT_ADDR` | `http://127.0.0.1:8200` | OpenBao URL |
| `OPENBAO_TOKEN` / `BAO_TOKEN` / `VAULT_TOKEN` | (required) | Auth token |
| `OPENBAO_KV_MOUNT` | `secret` | KV v2 mount |
| `OPENBAO_PASSKEYS_PREFIX` | `passkeys` | Passkey path prefix |
| `OPENBAO_PASSWORDS_PREFIX` | `passwords` | Password path prefix |

### Paths (same layout as openbao-passkeys)

| Kind | Path |
|------|------|
| Passkeys | `secret/data/passkeys/<credentialId>` |
| Passwords | `secret/data/passwords/<id>` |

Passkey records store both:
- `privateKeyBytes` — Ladybird P-256 scalar (base64url)
- `privateKeyJwk` — EC P-256 JWK (`d`/`x`/`y`) for [openbao-passkeys](https://github.com/codegod100/openbao-passkeys) interop

Registration `signCount` starts at `0`. Lists are cached in-process (~5 minutes); Password Manager **Refresh** clears the cache.

Password Manager masks secrets (`••••••••`) and copies via **Copy password** / double-click.

## Caveats

- Needs network egress to the OpenBao host (no D-Bus / gnome-keyring)
- Autofill fills empty username/password fields on document load, when a
  password `<input>` is inserted (SPAs), and on password-field focus
- Skips `autocomplete=off` / `new-password`; matches stored origin or host
- Form submit silently updates OpenBao when both username and password are present
- Prefer a narrowly scoped token outside local testing

## Apply

```bash
./packages/ladybird/webauthn/apply-overlay.sh /path/to/ladybird
./packages/ladybird/passwordmgr/apply-overlay.sh /path/to/ladybird
```

Nix package runs both when `enableSoftwarePasskeys` is true.
