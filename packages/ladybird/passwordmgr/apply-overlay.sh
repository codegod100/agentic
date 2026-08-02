#!/usr/bin/env bash
# Apply experimental GNOME Keyring password manager scaffold onto a Ladybird tree.
# Run after webauthn/apply-overlay.sh (replaces CredentialsContainer + passkey store wiring).
set -euo pipefail

overlay_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ladybird_root="${1:?usage: apply-overlay.sh /path/to/ladybird}"

if [[ ! -d "$ladybird_root/Libraries/LibWeb" || ! -d "$ladybird_root/UI/Qt" ]]; then
  echo "error: $ladybird_root does not look like a Ladybird checkout" >&2
  exit 1
fi

mkdir -p "$ladybird_root/Libraries/LibWeb/CredentialManagement"
mkdir -p "$ladybird_root/Libraries/LibWeb/WebAuthn"
mkdir -p "$ladybird_root/UI/Qt"

install -m 644 "$overlay_root"/Libraries/LibWeb/CredentialManagement/* \
  "$ladybird_root/Libraries/LibWeb/CredentialManagement/"
install -m 644 "$overlay_root"/Libraries/LibWeb/WebAuthn/SoftwarePasskeyAuthenticator.cpp \
  "$ladybird_root/Libraries/LibWeb/WebAuthn/SoftwarePasskeyAuthenticator.cpp"
install -m 644 "$overlay_root"/UI/Qt/PasswordManagerDialog.h \
  "$ladybird_root/UI/Qt/PasswordManagerDialog.h"
install -m 644 "$overlay_root"/UI/Qt/PasswordManagerDialog.cpp \
  "$ladybird_root/UI/Qt/PasswordManagerDialog.cpp"

cmake_lists="$ladybird_root/Libraries/LibWeb/CMakeLists.txt"
python3 - "$cmake_lists" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
changed = False

needle = "    CredentialManagement/PasswordCredentialOperations.cpp\n"
insert = needle + "    CredentialManagement/GnomeKeyringStore.cpp\n"
if "GnomeKeyringStore.cpp" not in text:
    if needle not in text:
        raise SystemExit("CMakeLists.txt: PasswordCredentialOperations.cpp line not found")
    text = text.replace(needle, insert, 1)
    changed = True

if "PkgConfig::LIBSECRET" not in text:
    marker = "target_link_libraries(LibWeb PRIVATE LibCore"
    idx = text.find(marker)
    if idx < 0:
        raise SystemExit("LibWeb target_link_libraries marker not found")
    hook = (
        "\nfind_package(PkgConfig REQUIRED)\n"
        "pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)\n"
        "target_link_libraries(LibWeb PRIVATE PkgConfig::LIBSECRET)\n\n"
    )
    text = text[:idx] + hook + text[idx:]
    changed = True

if changed:
    path.write_text(text)
    print("patched LibWeb CMakeLists.txt")
else:
    print("LibWeb CMakeLists.txt already patched")
PY

qt_cmake="$ladybird_root/UI/Qt/CMakeLists.txt"
python3 - "$qt_cmake" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "PasswordManagerDialog.cpp" in text:
    print("UI/Qt CMakeLists.txt already patched")
else:
    needle = "    Settings.cpp\n"
    if needle not in text:
        raise SystemExit("UI/Qt CMakeLists.txt: Settings.cpp line not found")
    path.write_text(text.replace(needle, needle + "    PasswordManagerDialog.cpp\n", 1))
    print("patched UI/Qt CMakeLists.txt")
PY

browser_window="$ladybird_root/UI/Qt/BrowserWindow.cpp"
python3 - "$browser_window" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "Password Manager" in text and "PasswordManagerDialog.h" in text:
    print("BrowserWindow.cpp already patched")
    raise SystemExit(0)

if "#include <UI/Qt/PasswordManagerDialog.h>" not in text:
    needle = "#include <QMenuBar>\n"
    if needle not in text:
        raise SystemExit("BrowserWindow.cpp: QMenuBar include not found")
    text = text.replace(needle, "#include <UI/Qt/PasswordManagerDialog.h>\n" + needle, 1)

needle = "edit_menu->addAction(create_application_action(*edit_menu, application.open_settings_page_action(), IncludeActionIcon::No));\n"
insert = needle + """
    auto* password_manager_action = new QAction("&Password Manager…", this);
    QObject::connect(password_manager_action, &QAction::triggered, this, [this] {
        auto* dialog = new PasswordManagerDialog(this);
        dialog->setAttribute(Qt::WA_DeleteOnClose);
        dialog->open();
    });
    edit_menu->addAction(password_manager_action);
"""
if needle not in text:
    raise SystemExit("BrowserWindow.cpp: settings action line not found")
text = text.replace(needle, insert, 1)
path.write_text(text)
print("patched BrowserWindow.cpp menu")
PY

echo "Password manager overlay applied to $ladybird_root"
