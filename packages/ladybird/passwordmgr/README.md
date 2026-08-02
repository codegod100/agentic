# Experimental password manager + GNOME Keyring

**Scaffold.** Not a production password manager.

## What it is

- `GnomeKeyringStore` — libsecret / Secret Service helper (GNOME Keyring, KWallet via org.freedesktop.secrets)
- CredMan hooks: `password` create / get / store + passkeys persisted to the same store
- Qt **Edit → Password Manager…** dialog to list / delete / manually add password entries

## Schema

Custom libsecret schema `org.ladybird.ExperimentalCredential`:

| attribute   | password        | passkey              |
|------------|-----------------|----------------------|
| `kind`     | `password`      | `passkey`            |
| `origin`   | serialized origin | (empty)            |
| `username` | username        | (empty)              |
| `rp_id`    | (empty)         | WebAuthn rpId        |
| `cred_id`  | (empty)         | base64url credential id |

Secret payload: password UTF-8, or passkey JSON `{user_handle,private_key,sign_count}` (base64 fields).

## Caveats

- WebContent talks to the session bus → needs **`--disable-sandbox`** (seccomp blocks D-Bus)
- No save prompt UI yet (silent store from CredMan APIs)
- No autofill into `<input>` — only `navigator.credentials` + the manager dialog
- Unlock / confirm prompts come from the desktop keyring daemon

## Apply

```bash
./packages/ladybird/webauthn/apply-overlay.sh /path/to/ladybird
./packages/ladybird/passwordmgr/apply-overlay.sh /path/to/ladybird
```

Nix package runs both when `enableSoftwarePasskeys` is true.
