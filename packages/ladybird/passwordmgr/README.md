# Experimental password manager + OpenBao

**Scaffold.** Not a production password manager.

Inspired by [openbao-passkeys](https://github.com/codegod100/openbao-passkeys): passwords and software passkeys live in OpenBao KV v2.

## What it is

- `OpenBaoStore` — sync libcurl client for OpenBao KV v2
- CredMan hooks: `password` create / get / store + passkeys persisted to the same store
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

Passkey records use Ladybird’s P-256 scalar under `privateKeyBytes` + `signCount` (registration starts at `0`). Extension JWK-only records are skipped.

## Caveats

- Needs network egress to the OpenBao host (no D-Bus / gnome-keyring)
- No save prompt UI yet (silent store from CredMan APIs)
- No autofill into `<input>` — only `navigator.credentials` + the manager dialog
- Prefer a narrowly scoped token outside local testing

## Apply

```bash
./packages/ladybird/webauthn/apply-overlay.sh /path/to/ladybird
./packages/ladybird/passwordmgr/apply-overlay.sh /path/to/ladybird
```

Nix package runs both when `enableSoftwarePasskeys` is true.
