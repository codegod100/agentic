#!/usr/bin/env bash
# Apply experimental OpenBao password manager scaffold onto a Ladybird tree.
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

# Drop previous libsecret backend if present.
rm -f "$ladybird_root/Libraries/LibWeb/CredentialManagement/GnomeKeyringStore.cpp" \
  "$ladybird_root/Libraries/LibWeb/CredentialManagement/GnomeKeyringStore.h"

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

# Migrate away from GnomeKeyringStore / libsecret if a prior overlay applied them.
if "CredentialManagement/GnomeKeyringStore.cpp" in text:
    text = text.replace("    CredentialManagement/GnomeKeyringStore.cpp\n", "")
    changed = True

needle = "    CredentialManagement/PasswordCredentialOperations.cpp\n"
insert = needle + "    CredentialManagement/OpenBaoStore.cpp\n"
if "OpenBaoStore.cpp" not in text:
    if needle not in text:
        raise SystemExit("CMakeLists.txt: PasswordCredentialOperations.cpp line not found")
    text = text.replace(needle, insert, 1)
    changed = True

if "CredentialManagement/PasswordAutofill.cpp" not in text:
    bao_needle = "    CredentialManagement/OpenBaoStore.cpp\n"
    if bao_needle not in text:
        raise SystemExit("CMakeLists.txt: OpenBaoStore.cpp line not found (needed for PasswordAutofill)")
    text = text.replace(bao_needle, bao_needle + "    CredentialManagement/PasswordAutofill.cpp\n", 1)
    changed = True

# Remove libsecret pkg-config block from older overlays.
libsecret_block = (
    "\nfind_package(PkgConfig REQUIRED)\n"
    "pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)\n"
    "target_link_libraries(LibWeb PRIVATE PkgConfig::LIBSECRET)\n"
)
if libsecret_block in text:
    text = text.replace(libsecret_block, "\n")
    changed = True
# Also handle without leading newline variants.
for fragment in (
    "find_package(PkgConfig REQUIRED)\npkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)\ntarget_link_libraries(LibWeb PRIVATE PkgConfig::LIBSECRET)\n",
    "pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)\n",
    "target_link_libraries(LibWeb PRIVATE PkgConfig::LIBSECRET)\n",
):
    if fragment in text and "LIBSECRET" in fragment:
        text = text.replace(fragment, "")
        changed = True

if "CURL::libcurl" not in text or "OpenBaoStore" in text:
    # Ensure LibWeb links libcurl for the OpenBao HTTP client.
    marker = "target_link_libraries(LibWeb PRIVATE LibCore"
    if "target_link_libraries(LibWeb PRIVATE CURL::libcurl)" not in text:
        idx = text.find(marker)
        if idx < 0:
            raise SystemExit("LibWeb target_link_libraries marker not found")
        hook = (
            "\n# OpenBao KV client (passwordmgr overlay)\n"
            "find_package(CURL REQUIRED)\n"
            "target_link_libraries(LibWeb PRIVATE CURL::libcurl)\n\n"
        )
        # Avoid duplicating if somehow already present nearby.
        if "OpenBao KV client" not in text:
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

# --- Form autofill / save hooks (surgical patches into huge upstream files) ---
python3 - "$ladybird_root" <<'PY'
from pathlib import Path
import sys
from typing import Optional, Tuple

root = Path(sys.argv[1])

def ensure_include(text: str, include: str, after: Optional[str] = None) -> Tuple[str, bool]:
    if include in text:
        return text, False
    needle = after or "#include <LibWeb/"
    idx = text.find(needle)
    if idx < 0:
        # fall back: first include block
        idx = text.find("#include ")
        if idx < 0:
            raise SystemExit(f"cannot insert include {include}")
    # insert before the found line
    line_start = text.rfind("\n", 0, idx) + 1
    return text[:line_start] + include + "\n" + text[line_start:], True

# HTMLInputElement: focus + inserted password fields
input_cpp = root / "Libraries/LibWeb/HTML/HTMLInputElement.cpp"
text = input_cpp.read_text()
changed = False
text2, c = ensure_include(
    text,
    "#include <LibWeb/CredentialManagement/PasswordAutofill.h>",
    "#include <LibWeb/HTML/HTMLInputElement.h>",
)
text, changed = text2, changed or c

focus_hook = "    // AD-HOC: OpenBao password autofill (passwordmgr overlay)\n    if (type_state() == TypeAttributeState::Password)\n        CredentialManagement::PasswordAutofill::try_fill_from_password_field(*this);\n\n"
if "PasswordAutofill::try_fill_from_password_field" not in text:
    needle = "void HTMLInputElement::did_receive_focus()\n{\n"
    if needle not in text:
        raise SystemExit("HTMLInputElement.cpp: did_receive_focus not found")
    text = text.replace(needle, needle + focus_hook, 1)
    changed = True

insert_hook = """    // AD-HOC: OpenBao password autofill when a password field appears (SPAs).
    if (type_state() == TypeAttributeState::Password && is_connected()) {
        queue_an_element_task(HTML::Task::Source::DOMManipulation, [this] {
            CredentialManagement::PasswordAutofill::try_fill_from_password_field(*this);
        });
    }

"""
if "OpenBao password autofill when a password field appears" not in text:
    needle = "void HTMLInputElement::form_associated_element_was_inserted()\n{\n    create_shadow_tree_if_needed();\n\n"
    if needle not in text:
        raise SystemExit("HTMLInputElement.cpp: form_associated_element_was_inserted not found")
    text = text.replace(needle, needle + insert_hook, 1)
    changed = True

if changed:
    input_cpp.write_text(text)
    print("patched HTMLInputElement.cpp autofill hooks")
else:
    print("HTMLInputElement.cpp autofill hooks already present")

# Document: fill after load
doc_cpp = root / "Libraries/LibWeb/DOM/Document.cpp"
text = doc_cpp.read_text()
changed = False
text2, c = ensure_include(
    text,
    "#include <LibWeb/CredentialManagement/PasswordAutofill.h>",
    "#include <LibWeb/DOM/Document.h>",
)
text, changed = text2, changed or c
# Environments for relevant_global_object / queue_global_task — usually already included
if "#include <LibWeb/HTML/Scripting/Environments.h>" not in text:
    text2, c = ensure_include(text, "#include <LibWeb/HTML/Scripting/Environments.h>", "#include <LibWeb/HTML/")
    text, changed = text2, changed or c
if "#include <LibWeb/HTML/EventLoop/Task.h>" not in text and "queue_global_task" not in text[:5000]:
    # Document.cpp already uses HTML::queue_global_task elsewhere; includes should exist.
    pass

load_hook = """    // AD-HOC: OpenBao password autofill (passwordmgr overlay)
    HTML::queue_global_task(HTML::Task::Source::DOMManipulation, HTML::relevant_global_object(*this), GC::create_function(heap(), [this] {
        CredentialManagement::PasswordAutofill::try_fill_document(*this);
    }));

"""
if "PasswordAutofill::try_fill_document" not in text:
    needle = "void Document::completely_finish_loading()\n{\n    m_ongoing_navigation_fetch_controller = nullptr;\n\n"
    if needle not in text:
        raise SystemExit("Document.cpp: completely_finish_loading not found")
    text = text.replace(needle, needle + load_hook, 1)
    changed = True

if changed:
    doc_cpp.write_text(text)
    print("patched Document.cpp autofill hook")
else:
    print("Document.cpp autofill hook already present")

# HTMLFormElement: silent save on submit
form_cpp = root / "Libraries/LibWeb/HTML/HTMLFormElement.cpp"
text = form_cpp.read_text()
changed = False
text2, c = ensure_include(
    text,
    "#include <LibWeb/CredentialManagement/PasswordAutofill.h>",
    "#include <LibWeb/HTML/HTMLFormElement.h>",
)
text, changed = text2, changed or c

save_hook = """    // AD-HOC: OpenBao password save (passwordmgr overlay)
    CredentialManagement::PasswordAutofill::maybe_save_from_form(*this);

"""
if "PasswordAutofill::maybe_save_from_form" not in text:
    needle = "WebIDL::ExceptionOr<void> HTMLFormElement::submit_form(GC::Ref<HTMLElement> submitter, SubmitFormOptions options)\n{\n    auto& vm = this->vm();\n    auto& realm = this->realm();\n\n"
    if needle not in text:
        raise SystemExit("HTMLFormElement.cpp: submit_form prologue not found")
    text = text.replace(needle, needle + save_hook, 1)
    changed = True

if changed:
    form_cpp.write_text(text)
    print("patched HTMLFormElement.cpp save hook")
else:
    print("HTMLFormElement.cpp save hook already present")
PY

echo "Password manager (OpenBao) overlay applied to $ladybird_root"
