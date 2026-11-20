#include "epub.h"

#include <QDateTime>
#include <QList>
#include <QStringList>

#include <array>

namespace {

quint32 crc32(const QByteArray &data) {
    static const std::array<quint32, 256> table = [] {
        std::array<quint32, 256> made{};
        for (quint32 i = 0; i < 256; ++i) {
            quint32 value = i;
            for (int bit = 0; bit < 8; ++bit)
                value = (value & 1) ? 0xEDB88320u ^ (value >> 1) : value >> 1;
            made[i] = value;
        }
        return made;
    }();
    quint32 crc = 0xFFFFFFFFu;
    for (const char byte : data)
        crc = table[(crc ^ quint8(byte)) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

void put16(QByteArray &out, quint16 value) {
    out.append(char(value & 0xFF));
    out.append(char(value >> 8));
}

void put32(QByteArray &out, quint32 value) {
    put16(out, quint16(value & 0xFFFF));
    put16(out, quint16(value >> 16));
}

// A ZIP archive whose files are stored as they are. An EPUB needs its
// first file uncompressed anyway, and a book's text is small.
class Archive {
public:
    void add(const QByteArray &name, const QByteArray &content) {
        const quint32 offset = quint32(m_files.size());
        const quint32 crc = crc32(content);
        const auto header = [&](QByteArray &out) {
            put16(out, 10);       // version needed
            put16(out, 0x0800);   // names are UTF-8
            put16(out, 0);        // stored
            put16(out, m_time);
            put16(out, m_date);
            put32(out, crc);
            put32(out, quint32(content.size()));
            put32(out, quint32(content.size()));
            put16(out, quint16(name.size()));
            put16(out, 0);        // no extra field
        };

        put32(m_files, 0x04034b50);
        header(m_files);
        m_files.append(name);
        m_files.append(content);

        put32(m_directory, 0x02014b50);
        put16(m_directory, 20);   // made by
        header(m_directory);
        put16(m_directory, 0);    // comment
        put16(m_directory, 0);    // disk
        put16(m_directory, 0);    // internal attributes
        put32(m_directory, 0);    // external attributes
        put32(m_directory, offset);
        m_directory.append(name);
        ++m_count;
    }

    QByteArray bytes() const {
        QByteArray out = m_files + m_directory;
        put32(out, 0x06054b50);
        put16(out, 0);
        put16(out, 0);
        put16(out, m_count);
        put16(out, m_count);
        put32(out, quint32(m_directory.size()));
        put32(out, quint32(m_files.size()));
        put16(out, 0);
        return out;
    }

private:
    QByteArray m_files;
    QByteArray m_directory;
    quint16 m_count = 0;
    // One fixed stamp, 1 January 2026, so the same book makes the same file.
    quint16 m_time = 0;
    quint16 m_date = quint16(((2026 - 1980) << 9) | (1 << 5) | 1);
};

// Characters XML has no place for would make the whole book unreadable.
QString escaped(const QString &text) {
    QString out;
    for (const QChar c : text) {
        if (c.unicode() < 0x20 && c != '\n' && c != '\t')
            continue;
        out += c;
    }
    return out.toHtmlEscaped();
}

const char *containerXml = R"(<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
)";

const char *styleCss = R"(body { margin: 5%; line-height: 1.5; font-family: serif; }
h1 { margin-top: 20%; text-align: center; }
.author { text-align: center; margin-bottom: 20%; }
p { margin: 0 0 1em 0; }
)";

} // namespace

QString Epub::page(const QString &title, const QString &author, const QString &text) {
    QString body;
    QString normal = text;
    normal.replace("\r\n", "\n");
    QStringList lines;
    const auto close = [&] {
        if (!lines.isEmpty())
            body += "    <p>" + lines.join("<br/>\n      ") + "</p>\n";
        lines.clear();
    };
    for (const QString &line : normal.split('\n')) {
        if (line.trimmed().isEmpty())
            close();
        else
            lines << escaped(line);
    }
    close();

    return QStringLiteral(R"(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta charset="UTF-8"/>
    <title>%1</title>
    <link rel="stylesheet" type="text/css" href="style.css"/>
  </head>
  <body>
    <h1>%1</h1>
%2%3  </body>
</html>
)").arg(escaped(title),
        author.isEmpty() ? QString() : "    <p class=\"author\">" + escaped(author) + "</p>\n",
        body);
}

QByteArray Epub::write(const QString &id, const QString &title, const QString &author, const QString &text) {
    const QString modified = QDateTime::currentDateTimeUtc().toString("yyyy-MM-ddTHH:mm:ssZ");
    const QString package = QStringLiteral(R"(<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:uuid:%1</dc:identifier>
    <dc:title>%2</dc:title>
%3    <dc:language>und</dc:language>
    <meta property="dcterms:modified">%4</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="book" href="book.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="book"/>
  </spine>
</package>
)").arg(escaped(id), escaped(title),
        author.isEmpty() ? QString() : "    <dc:creator>" + escaped(author) + "</dc:creator>\n",
        modified);

    const QString nav = QStringLiteral(R"(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <meta charset="UTF-8"/>
    <title>%1</title>
  </head>
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="book.xhtml">%1</a></li>
      </ol>
    </nav>
  </body>
</html>
)").arg(escaped(title));

    Archive archive;
    // A reader tells an EPUB by this first, uncompressed file.
    archive.add("mimetype", "application/epub+zip");
    archive.add("META-INF/container.xml", containerXml);
    archive.add("OEBPS/content.opf", package.toUtf8());
    archive.add("OEBPS/nav.xhtml", nav.toUtf8());
    archive.add("OEBPS/book.xhtml", page(title, author, text).toUtf8());
    archive.add("OEBPS/style.css", styleCss);
    return archive.bytes();
}
