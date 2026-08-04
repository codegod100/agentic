# Experimental software passkeys (WebAuthn)

**For the lulz.** This is not a production WebAuthn stack.

## What it is

A minimal in-process ES256 software authenticator wired into Ladybird’s
`navigator.credentials.create` / `.get` when `options.publicKey` is present.

- Attestation format: `none`
- UV/UP flags always set
- Credentials stored in a process-local vector (lost on restart; not IPC-safe)
- No CTAP, no OS authenticator, no conditional mediation, no hybrid/caBLE

## Apply

```bash
./packages/ladybird/webauthn/apply-overlay.sh /path/to/ladybird
```

The Ladybird Nix package runs this from `postPatch` when
`enableSoftwarePasskeys` is true (default on).

## Try

After building Ladybird with the overlay:

1. Open `https://webauthn.io` (or similar)
2. Register — should get a `PublicKeyCredential` instead of `NotImplemented`
3. Authenticate in the same browser session

## Non-goals (yet)

Platform authenticators, discoverable credential UI, secure storage, sandbox IPC,
full WPT WebAuthn suite, attestation beyond `none`.
