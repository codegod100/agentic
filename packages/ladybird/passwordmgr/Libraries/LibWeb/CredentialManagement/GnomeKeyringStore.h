/*
 * Experimental libsecret (GNOME Keyring / Secret Service) backend.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#pragma once

#include <AK/ByteBuffer.h>
#include <AK/ByteString.h>
#include <AK/Error.h>
#include <AK/Optional.h>
#include <AK/Vector.h>

namespace Web::CredentialManagement {

struct KeyringPasswordEntry {
    ByteString origin;
    ByteString username;
    ByteString password;
    ByteString item_path; // libsecret object path / label helper
};

struct KeyringPasskeyEntry {
    ByteString rp_id;
    ByteString credential_id_b64;
    ByteBuffer user_handle;
    ByteBuffer private_key_bytes;
    u32 sign_count { 0 };
    ByteString item_path;
};

// Thin Secret Service wrapper. Requires a running session keyring and D-Bus.
class GnomeKeyringStore {
public:
    static ErrorOr<void> store_password(ByteString const& origin, ByteString const& username, ByteString const& password);
    static ErrorOr<Optional<KeyringPasswordEntry>> find_password(ByteString const& origin, Optional<ByteString> const& username = {});
    static ErrorOr<Vector<KeyringPasswordEntry>> list_passwords();
    static ErrorOr<void> delete_password(ByteString const& origin, ByteString const& username);

    static ErrorOr<void> store_passkey(KeyringPasskeyEntry const&);
    static ErrorOr<Optional<KeyringPasskeyEntry>> find_passkey(ByteString const& rp_id);
    static ErrorOr<Vector<KeyringPasskeyEntry>> list_passkeys();
    static ErrorOr<void> delete_passkey(ByteString const& rp_id, ByteString const& credential_id_b64);
};

}
