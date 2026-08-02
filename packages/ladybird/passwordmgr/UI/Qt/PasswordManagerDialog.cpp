/*
 * Experimental password manager dialog (GNOME Keyring backed).
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <AK/StringView.h>
#include <LibWeb/CredentialManagement/GnomeKeyringStore.h>
#include <UI/Qt/PasswordManagerDialog.h>

#include <QHBoxLayout>
#include <QHeaderView>
#include <QItemSelectionModel>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QTabWidget>
#include <QTableWidget>
#include <QVBoxLayout>

namespace {

ByteString qstring_to_byte_string(QString const& string)
{
    auto utf8 = string.toUtf8();
    return ByteString { StringView { utf8.constData(), static_cast<size_t>(utf8.size()) } };
}

QString error_to_qstring(Error const& error)
{
    auto view = error.string_literal();
    return QString::fromUtf8(view.characters_without_null_termination(), static_cast<int>(view.length()));
}

}

namespace Ladybird {

PasswordManagerDialog::PasswordManagerDialog(QWidget* parent)
    : QDialog(parent)
{
    setWindowTitle("Password Manager");
    setMinimumSize(640, 420);

    auto* root = new QVBoxLayout(this);
    auto* tabs = new QTabWidget(this);
    root->addWidget(tabs);

    auto* passwords_page = new QWidget(tabs);
    auto* passwords_layout = new QVBoxLayout(passwords_page);

    m_table = new QTableWidget(0, 3, passwords_page);
    m_table->setHorizontalHeaderLabels({ "Origin", "Username", "Password" });
    m_table->horizontalHeader()->setStretchLastSection(true);
    m_table->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    passwords_layout->addWidget(m_table);

    auto* form = new QHBoxLayout();
    m_origin = new QLineEdit(passwords_page);
    m_origin->setPlaceholderText("https://example.com");
    m_username = new QLineEdit(passwords_page);
    m_username->setPlaceholderText("username");
    m_password = new QLineEdit(passwords_page);
    m_password->setPlaceholderText("password");
    m_password->setEchoMode(QLineEdit::Password);
    form->addWidget(m_origin);
    form->addWidget(m_username);
    form->addWidget(m_password);
    passwords_layout->addLayout(form);

    auto* buttons = new QHBoxLayout();
    auto* add_btn = new QPushButton("Add / Update", passwords_page);
    auto* remove_btn = new QPushButton("Delete selected", passwords_page);
    auto* refresh_btn = new QPushButton("Refresh", passwords_page);
    buttons->addWidget(add_btn);
    buttons->addWidget(remove_btn);
    buttons->addStretch();
    buttons->addWidget(refresh_btn);
    passwords_layout->addLayout(buttons);

    auto* passkeys_page = new QWidget(tabs);
    auto* passkeys_layout = new QVBoxLayout(passkeys_page);
    passkeys_layout->addWidget(new QLabel(
        "Passkeys are stored in the same GNOME Keyring schema "
        "(kind=passkey). Create/get them via navigator.credentials "
        "on sites like webauthn.io while running with --disable-sandbox.",
        passkeys_page));
    passkeys_layout->addStretch();

    tabs->addTab(passwords_page, "Passwords");
    tabs->addTab(passkeys_page, "Passkeys");

    connect(add_btn, &QPushButton::clicked, this, &PasswordManagerDialog::add_password);
    connect(remove_btn, &QPushButton::clicked, this, &PasswordManagerDialog::remove_selected);
    connect(refresh_btn, &QPushButton::clicked, this, &PasswordManagerDialog::refresh);

    refresh();
}

void PasswordManagerDialog::refresh()
{
    m_table->setRowCount(0);
    auto listed = Web::CredentialManagement::GnomeKeyringStore::list_passwords();
    if (listed.is_error()) {
        QMessageBox::warning(this, "Keyring",
            QString("Could not list passwords:\n%1\n\nIs gnome-keyring running? WebContent also needs --disable-sandbox for D-Bus.")
                .arg(error_to_qstring(listed.error())));
        return;
    }
    for (auto const& entry : listed.value()) {
        int row = m_table->rowCount();
        m_table->insertRow(row);
        m_table->setItem(row, 0, new QTableWidgetItem(QString::fromUtf8(entry.origin.characters())));
        m_table->setItem(row, 1, new QTableWidgetItem(QString::fromUtf8(entry.username.characters())));
        m_table->setItem(row, 2, new QTableWidgetItem(QString::fromUtf8(entry.password.characters())));
    }
}

void PasswordManagerDialog::add_password()
{
    auto origin = m_origin->text().trimmed();
    auto username = m_username->text().trimmed();
    auto password = m_password->text();
    if (origin.isEmpty() || username.isEmpty() || password.isEmpty()) {
        QMessageBox::information(this, "Password Manager", "Origin, username, and password are required.");
        return;
    }
    auto result = Web::CredentialManagement::GnomeKeyringStore::store_password(
        qstring_to_byte_string(origin),
        qstring_to_byte_string(username),
        qstring_to_byte_string(password));
    if (result.is_error()) {
        QMessageBox::warning(this, "Keyring", error_to_qstring(result.error()));
        return;
    }
    m_password->clear();
    refresh();
}

void PasswordManagerDialog::remove_selected()
{
    auto rows = m_table->selectionModel()->selectedRows();
    if (rows.isEmpty())
        return;
    int row = rows.first().row();
    auto origin = m_table->item(row, 0)->text();
    auto username = m_table->item(row, 1)->text();
    auto result = Web::CredentialManagement::GnomeKeyringStore::delete_password(
        qstring_to_byte_string(origin),
        qstring_to_byte_string(username));
    if (result.is_error()) {
        QMessageBox::warning(this, "Keyring", error_to_qstring(result.error()));
        return;
    }
    refresh();
}

}
