#!/usr/bin/env bash
# Copy experimental WebAuthn overlay into a Ladybird source tree and patch build files.
set -euo pipefail

overlay_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ladybird_root="${1:?usage: apply-overlay.sh /path/to/ladybird}"

if [[ ! -d "$ladybird_root/Libraries/LibWeb" ]]; then
  echo "error: $ladybird_root does not look like a Ladybird checkout" >&2
  exit 1
fi

mkdir -p "$ladybird_root/Libraries/LibWeb/WebAuthn"
mkdir -p "$ladybird_root/Libraries/LibWeb/CredentialManagement"

install -m 644 "$overlay_root"/Libraries/LibWeb/WebAuthn/* \
  "$ladybird_root/Libraries/LibWeb/WebAuthn/"
install -m 644 "$overlay_root"/Libraries/LibWeb/CredentialManagement/CredentialsContainer.cpp \
  "$ladybird_root/Libraries/LibWeb/CredentialManagement/CredentialsContainer.cpp"

idl_cmake="$ladybird_root/Libraries/LibWeb/idl_files.cmake"
if ! grep -q 'WebAuthn/PublicKeyCredential' "$idl_cmake"; then
  python3 - <<PY
from pathlib import Path
path = Path("$idl_cmake")
text = path.read_text()
needle = "libweb_js_bindings(CredentialManagement/PasswordCredential)\n"
insert = needle + (
    "libweb_js_bindings(WebAuthn/AuthenticatorResponse)\n"
    "libweb_js_bindings(WebAuthn/AuthenticatorAttestationResponse)\n"
    "libweb_js_bindings(WebAuthn/AuthenticatorAssertionResponse)\n"
    "libweb_js_bindings(WebAuthn/PublicKeyCredential)\n"
)
if needle not in text:
    raise SystemExit("idl_files.cmake: PasswordCredential binding line not found")
if "WebAuthn/PublicKeyCredential" not in text:
    path.write_text(text.replace(needle, insert, 1))
print("patched idl_files.cmake")
PY
fi

cmake_lists="$ladybird_root/Libraries/LibWeb/CMakeLists.txt"
if ! grep -q 'WebAuthn/PublicKeyCredential.cpp' "$cmake_lists"; then
  python3 - <<PY
from pathlib import Path
path = Path("$cmake_lists")
text = path.read_text()
needle = "    CredentialManagement/PasswordCredentialOperations.cpp\n"
insert = needle + (
    "    WebAuthn/AuthenticatorResponse.cpp\n"
    "    WebAuthn/AuthenticatorAttestationResponse.cpp\n"
    "    WebAuthn/AuthenticatorAssertionResponse.cpp\n"
    "    WebAuthn/PublicKeyCredential.cpp\n"
    "    WebAuthn/SoftwarePasskeyAuthenticator.cpp\n"
)
if needle not in text:
    raise SystemExit("CMakeLists.txt: PasswordCredentialOperations.cpp line not found")
if "WebAuthn/PublicKeyCredential.cpp" not in text:
    path.write_text(text.replace(needle, insert, 1))
print("patched CMakeLists.txt")
PY
fi

forward_h="$ladybird_root/Libraries/LibWeb/Forward.h"
if ! grep -q 'namespace Web::WebAuthn' "$forward_h"; then
  python3 - <<PY
from pathlib import Path
path = Path("$forward_h")
text = path.read_text()
needle = """namespace Web::CredentialManagement {

class Credential;
class CredentialsContainer;
class FederatedCredential;
class PasswordCredential;

}
"""
insert = needle + """
namespace Web::WebAuthn {

class AuthenticatorResponse;
class AuthenticatorAttestationResponse;
class AuthenticatorAssertionResponse;
class PublicKeyCredential;

}
"""
if needle not in text:
    raise SystemExit("Forward.h: CredentialManagement block not found")
if "namespace Web::WebAuthn" not in text:
    path.write_text(text.replace(needle, insert, 1))
print("patched Forward.h")
PY
fi

echo "WebAuthn overlay applied to $ladybird_root"
