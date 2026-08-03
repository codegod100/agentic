/*
 * Experimental libsecret backend for Ladybird CredMan / passkeys.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <AK/Base64.h>
#include <AK/Format.h>
#include <AK/StringBuilder.h>
#include <LibWeb/CredentialManagement/GnomeKeyringStore.h>
#include <libsecret/secret.h>
#include <string.h>

namespace Web::CredentialManagement {

static SecretSchema const& credential_schema()
{
    // Zero-init reserved* fields (required under -Werror=missing-field-initializers).
    static SecretSchema schema {};
    static bool const initialized = [] {
        schema.name = "org.ladybird.ExperimentalCredential";
        schema.flags = SECRET_SCHEMA_NONE;
        schema.attributes[0] = { "kind", SECRET_SCHEMA_ATTRIBUTE_STRING };
        schema.attributes[1] = { "origin", SECRET_SCHEMA_ATTRIBUTE_STRING };
        schema.attributes[2] = { "username", SECRET_SCHEMA_ATTRIBUTE_STRING };
        schema.attributes[3] = { "rp_id", SECRET_SCHEMA_ATTRIBUTE_STRING };
        schema.attributes[4] = { "cred_id", SECRET_SCHEMA_ATTRIBUTE_STRING };
        schema.attributes[5] = { nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING };
        return true;
    }();
    (void)initialized;
    return schema;
}

static Error map_gerror(GError* error, char const* fallback)
{
    if (error) {
        // Error only stores StringView; keep a stable literal for callers.
        dbgln("libsecret error: {}", error->message);
        g_error_free(error);
    }
    return Error::from_string_view(StringView { fallback, strlen(fallback) });
}

static ByteString encode_passkey_secret(KeyringPasskeyEntry const& entry)
{
    auto user_b64 = MUST(encode_base64(entry.user_handle));
    auto key_b64 = MUST(encode_base64(entry.private_key_bytes));
    StringBuilder builder;
    builder.append("{\"user_handle\":\""sv);
    builder.append(user_b64.bytes());
    builder.append("\",\"private_key\":\""sv);
    builder.append(key_b64.bytes());
    builder.append("\",\"sign_count\":"sv);
    builder.appendff("{}", entry.sign_count);
    builder.append('}');
    return builder.to_byte_string();
}

static ErrorOr<KeyringPasskeyEntry> decode_passkey_secret(ByteString const& rp_id, ByteString const& cred_id, ByteString const& secret)
{
    // Minimal parser for {"user_handle":"...","private_key":"...","sign_count":N}
    auto extract = [&](StringView key) -> Optional<ByteString> {
        auto pattern = ByteString::formatted("\"{}\":\"", key);
        auto start = secret.find(pattern);
        if (!start.has_value())
            return {};
        auto from = *start + pattern.length();
        auto end = secret.find('"', from);
        if (!end.has_value())
            return {};
        return secret.substring(from, *end - from);
    };

    auto user_b64 = extract("user_handle"sv);
    auto key_b64 = extract("private_key"sv);
    if (!user_b64.has_value() || !key_b64.has_value())
        return Error::from_string_literal("Malformed passkey secret");

    u32 sign_count = 0;
    auto sc_key = "\"sign_count\":"sv;
    if (auto sc = secret.find(sc_key); sc.has_value()) {
        auto from = *sc + sc_key.length();
        sign_count = secret.substring(from).to_number<u32>().value_or(0);
    }

    auto user = TRY(decode_base64(*user_b64));
    auto key = TRY(decode_base64(*key_b64));
    return KeyringPasskeyEntry {
        .rp_id = rp_id,
        .credential_id_b64 = cred_id,
        .user_handle = move(user),
        .private_key_bytes = move(key),
        .sign_count = sign_count,
        .item_path = {},
    };
}

ErrorOr<void> GnomeKeyringStore::store_password(ByteString const& origin, ByteString const& username, ByteString const& password)
{
    GError* error = nullptr;
    auto label = ByteString::formatted("Ladybird password: {} @ {}", username, origin);
    gboolean ok = secret_password_store_sync(
        &credential_schema(),
        SECRET_COLLECTION_DEFAULT,
        label.characters(),
        password.characters(),
        nullptr,
        &error,
        "kind", "password",
        "origin", origin.characters(),
        "username", username.characters(),
        "rp_id", "",
        "cred_id", "",
        nullptr);
    if (!ok)
        return map_gerror(error, "secret_password_store_sync failed");
    return {};
}

ErrorOr<Optional<KeyringPasswordEntry>> GnomeKeyringStore::find_password(ByteString const& origin, Optional<ByteString> const& username)
{
    GError* error = nullptr;
    gchar* secret = nullptr;
    if (username.has_value()) {
        secret = secret_password_lookup_sync(
            &credential_schema(),
            nullptr,
            &error,
            "kind", "password",
            "origin", origin.characters(),
            "username", username->characters(),
            nullptr);
    } else {
        secret = secret_password_lookup_sync(
            &credential_schema(),
            nullptr,
            &error,
            "kind", "password",
            "origin", origin.characters(),
            nullptr);
    }
    if (error)
        return map_gerror(error, "secret_password_lookup_sync failed");
    if (!secret)
        return OptionalNone {};

    KeyringPasswordEntry entry {
        .origin = origin,
        .username = username.value_or({}),
        .password = ByteString { secret },
        .item_path = {},
    };
    secret_password_free(secret);

    if (entry.username.is_empty()) {
        // Lookup without username: fill username from a search attribute if possible.
        auto listed = TRY(list_passwords());
        for (auto const& item : listed) {
            if (item.origin == origin) {
                entry.username = item.username;
                break;
            }
        }
    }
    return entry;
}

ErrorOr<Vector<KeyringPasswordEntry>> GnomeKeyringStore::list_passwords()
{
    GError* error = nullptr;
    auto* service = secret_service_get_sync(SECRET_SERVICE_LOAD_COLLECTIONS, nullptr, &error);
    if (!service)
        return map_gerror(error, "secret_service_get_sync failed");

    GHashTable* attrs = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    g_hash_table_insert(attrs, g_strdup("kind"), g_strdup("password"));

    GList* items = secret_service_search_sync(
        service,
        &credential_schema(),
        attrs,
        static_cast<SecretSearchFlags>(SECRET_SEARCH_ALL | SECRET_SEARCH_UNLOCK | SECRET_SEARCH_LOAD_SECRETS),
        nullptr,
        &error);
    g_hash_table_unref(attrs);
    g_object_unref(service);

    if (error)
        return map_gerror(error, "secret_service_search_sync failed");

    Vector<KeyringPasswordEntry> out;
    for (GList* it = items; it; it = it->next) {
        auto* item = SECRET_ITEM(it->data);
        auto* attributes = secret_item_get_attributes(item);
        auto* value = secret_item_get_secret(item);
        char const* origin = static_cast<char const*>(g_hash_table_lookup(attributes, "origin"));
        char const* username = static_cast<char const*>(g_hash_table_lookup(attributes, "username"));
        ByteString password;
        if (value)
            password = ByteString { secret_value_get_text(value) };
        out.append(KeyringPasswordEntry {
            .origin = origin ? ByteString { origin } : ByteString {},
            .username = username ? ByteString { username } : ByteString {},
            .password = move(password),
            .item_path = ByteString { secret_item_get_label(item) },
        });
        g_hash_table_unref(attributes);
    }
    g_list_free_full(items, g_object_unref);
    return out;
}

ErrorOr<void> GnomeKeyringStore::delete_password(ByteString const& origin, ByteString const& username)
{
    GError* error = nullptr;
    gboolean ok = secret_password_clear_sync(
        &credential_schema(),
        nullptr,
        &error,
        "kind", "password",
        "origin", origin.characters(),
        "username", username.characters(),
        nullptr);
    if (!ok && error)
        return map_gerror(error, "secret_password_clear_sync failed");
    if (error)
        g_error_free(error);
    return {};
}

ErrorOr<void> GnomeKeyringStore::store_passkey(KeyringPasskeyEntry const& entry)
{
    GError* error = nullptr;
    auto secret = encode_passkey_secret(entry);
    auto label = ByteString::formatted("Ladybird passkey: {}", entry.rp_id);
    gboolean ok = secret_password_store_sync(
        &credential_schema(),
        SECRET_COLLECTION_DEFAULT,
        label.characters(),
        secret.characters(),
        nullptr,
        &error,
        "kind", "passkey",
        "origin", "",
        "username", "",
        "rp_id", entry.rp_id.characters(),
        "cred_id", entry.credential_id_b64.characters(),
        nullptr);
    if (!ok)
        return map_gerror(error, "secret_password_store_sync failed");
    return {};
}

ErrorOr<Optional<KeyringPasskeyEntry>> GnomeKeyringStore::find_passkey(ByteString const& rp_id)
{
    auto all = TRY(list_passkeys());
    for (auto& entry : all) {
        if (entry.rp_id == rp_id)
            return entry;
    }
    return OptionalNone {};
}

ErrorOr<Vector<KeyringPasskeyEntry>> GnomeKeyringStore::list_passkeys()
{
    GError* error = nullptr;
    auto* service = secret_service_get_sync(SECRET_SERVICE_LOAD_COLLECTIONS, nullptr, &error);
    if (!service)
        return map_gerror(error, "secret_service_get_sync failed");

    GHashTable* attrs = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    g_hash_table_insert(attrs, g_strdup("kind"), g_strdup("passkey"));

    GList* items = secret_service_search_sync(
        service,
        &credential_schema(),
        attrs,
        static_cast<SecretSearchFlags>(SECRET_SEARCH_ALL | SECRET_SEARCH_UNLOCK | SECRET_SEARCH_LOAD_SECRETS),
        nullptr,
        &error);
    g_hash_table_unref(attrs);
    g_object_unref(service);

    if (error)
        return map_gerror(error, "secret_service_search_sync failed");

    Vector<KeyringPasskeyEntry> out;
    for (GList* it = items; it; it = it->next) {
        auto* item = SECRET_ITEM(it->data);
        auto* attributes = secret_item_get_attributes(item);
        auto* value = secret_item_get_secret(item);
        char const* rp_id = static_cast<char const*>(g_hash_table_lookup(attributes, "rp_id"));
        char const* cred_id = static_cast<char const*>(g_hash_table_lookup(attributes, "cred_id"));
        if (value && rp_id && cred_id) {
            auto decoded = decode_passkey_secret(ByteString { rp_id }, ByteString { cred_id }, ByteString { secret_value_get_text(value) });
            if (!decoded.is_error()) {
                auto entry = decoded.release_value();
                entry.item_path = ByteString { secret_item_get_label(item) };
                out.append(move(entry));
            }
        }
        g_hash_table_unref(attributes);
    }
    g_list_free_full(items, g_object_unref);
    return out;
}

ErrorOr<void> GnomeKeyringStore::delete_passkey(ByteString const& rp_id, ByteString const& credential_id_b64)
{
    GError* error = nullptr;
    gboolean ok = secret_password_clear_sync(
        &credential_schema(),
        nullptr,
        &error,
        "kind", "passkey",
        "rp_id", rp_id.characters(),
        "cred_id", credential_id_b64.characters(),
        nullptr);
    if (!ok && error)
        return map_gerror(error, "secret_password_clear_sync failed");
    if (error)
        g_error_free(error);
    return {};
}

}
