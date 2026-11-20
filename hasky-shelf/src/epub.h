#pragma once

#include <QByteArray>
#include <QString>

// A written book as one EPUB file: what any reader app opens, and what
// another shelf takes back in.
namespace Epub {

// The whole file's bytes. The id is the book's own, so the same book shared
// twice is the same publication to a reader.
QByteArray write(const QString &id, const QString &title, const QString &author, const QString &text);

// The text as the book's page: a blank line parts two paragraphs, and a
// line break inside one stays a line break, so verse keeps its lines.
QString page(const QString &title, const QString &author, const QString &text);

} // namespace Epub
