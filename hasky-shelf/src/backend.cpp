#include "backend.h"

#include "epub.h"
#include "filepicker.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QCoreApplication>
#include <QDir>
#include <QEventLoopLocker>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QSaveFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextDocument>
#include <QThreadPool>
#include <QUuid>

#include <algorithm>
#include <memory>

namespace {

// How many cover colors the window draws from the theme's palette.
constexpr int tints = 6;

// Written atomically, and never by truncating in place: a folder that can't
// take a temp file fails the save rather than risking the book.
bool save(const QString &path, const QByteArray &content) {
    QSaveFile file(path);
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(content);
    return file.commit();
}

// The formats a file can have to go on the shelf.
const QStringList bookFormats = {"pdf", "epub"};

// A file's name as a title: "paper_satellites-v2.pdf" reads as
// "paper satellites v2" on the cover.
QString titleFrom(const QString &fileName) {
    QString title = QFileInfo(fileName).completeBaseName();
    title.replace(QRegularExpression("[_-]+"), " ");
    return title.simplified();
}

// A title as a file name: nothing that parts folders, hides the file or
// overruns what a file system takes.
QString fileNameFrom(const QString &title) {
    QString name;
    for (const QChar c : title) {
        if (c == '/' || c == '\\' || c == QChar(0) || c.category() == QChar::Other_Control)
            name += ' ';
        else
            name += c;
    }
    name = name.simplified();
    while (name.startsWith('.'))
        name.remove(0, 1);
    while (name.toUtf8().size() > 120)
        name.chop(1);
    return name.trimmed();
}

} // namespace

Backend::Backend(const QString &root, FilePicker *picker, QObject *parent)
    : QObject(parent),
      m_root(root.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) : root),
      m_shareFolder(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)),
      m_picker(picker) {
    if (m_picker) {
        connect(m_picker, &FilePicker::booksSelected, this, &Backend::addFiles);
        connect(m_picker, &FilePicker::failed, this, &Backend::setError);
    }
    load();
}

void Backend::setError(const QString &error) {
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

void Backend::load() {
    QVariantList books;
    const QDir shelf(m_root + "/books");
    for (const QString &id : shelf.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        QFile file(shelf.filePath(id + "/book.json"));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject json = QJsonDocument::fromJson(file.readAll()).object();
        if (json.isEmpty())
            continue;
        QVariantMap book = json.toVariantMap();
        book["id"] = id;
        // The color is a property of the book, not of its place on the
        // shelf, so it stays the same as books come and go around it.
        book["tint"] = int(qHash(id) % tints);
        books << book;
    }
    // Oldest first: a new book lands at the end of the shelf.
    std::stable_sort(books.begin(), books.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("created").toString() < b.toMap().value("created").toString();
    });
    m_books = books;
    emit booksChanged();
}

QString Backend::createBook(const QString &title, const QString &author) {
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString folder = m_root + "/books/" + id;
    if (!QDir().mkpath(folder)) {
        setError(tr("The shelf folder could not be created."));
        return {};
    }

    QJsonObject json;
    json["title"] = title.trimmed().isEmpty() ? tr("Untitled") : title.trimmed();
    json["author"] = author.trimmed();
    json["kind"] = "written";
    json["file"] = "book.md";
    json["created"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);

    if (!save(folder + "/book.md", QByteArray()) || !save(folder + "/book.json", QJsonDocument(json).toJson())) {
        QDir(folder).removeRecursively();
        setError(tr("The book could not be saved."));
        return {};
    }

    setError({});
    load();
    return id;
}

QVariantMap Backend::book(const QString &id) const {
    for (const QVariant &entry : m_books) {
        const QVariantMap book = entry.toMap();
        if (book.value("id").toString() == id)
            return book;
    }
    return {};
}

QString Backend::textPath(const QString &id) const {
    if (book(id).value("kind").toString() != "written")
        return {};
    return m_root + "/books/" + id + "/book.md";
}

QString Backend::filePath(const QString &id) const {
    const QVariantMap found = book(id);
    const QString format = found.value("format").toString();
    if (found.value("kind").toString() != "file" || !bookFormats.contains(format))
        return {};
    return m_root + "/books/" + id + "/book." + format;
}

bool Backend::openInReader(const QString &id) {
    const QString path = filePath(id);
    if (path.isEmpty() || !QFile::exists(path) || !QDesktopServices::openUrl(QUrl::fromLocalFile(path))) {
        setError(tr("The book could not be opened."));
        return false;
    }
    setError({});
    return true;
}

void Backend::shareBook(const QString &id) {
    const QVariantMap found = book(id);
    const bool written = found.value("kind").toString() == "written";
    const QString source = written ? textPath(id) : filePath(id);
    if (source.isEmpty() || !QFile::exists(source)) {
        setError(tr("The book could not be shared."));
        return;
    }
    setError({});

    const QString title = found.value("title").toString();
    const QString author = found.value("author").toString();
    const QString format = written ? QStringLiteral("epub") : found.value("format").toString();
    QString name = fileNameFrom(title);
    if (name.isEmpty())
        name = "book";
    const QString folder = m_shareFolder;

    // An added book can be large, so sharing runs on a worker like adding.
    auto alive = std::make_shared<QEventLoopLocker>();
    QPointer<Backend> self(this);
    QThreadPool::globalInstance()->start([self, alive, id, written, source, title, author, format, name, folder] {
        QString path;
        bool done = false;
        if (QDir().mkpath(folder)) {
            QByteArray content;
            bool read = true;
            if (written) {
                QFile text(source);
                read = text.open(QIODevice::ReadOnly);
                if (read)
                    content = Epub::write(id, title, author, QString::fromUtf8(text.readAll()));
            }
            // "Title.epub", then "Title 2.epub": a copy shared before is
            // never written over. Each name is claimed by creating it.
            for (int n = 1; read && n < 1000 && !done; ++n) {
                path = folder + "/" + name + (n == 1 ? QString() : " " + QString::number(n)) + "." + format;
                if (QFile::exists(path))
                    continue;
                if (written) {
                    QFile file(path);
                    if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly))
                        continue;
                    done = file.write(content) == content.size() && file.flush();
                    file.close();
                    if (!done) {
                        file.remove();
                        break;
                    }
                } else {
                    done = QFile::copy(source, path);
                    if (!done && !QFile::exists(path))
                        break;
                }
            }
        }
        QMetaObject::invokeMethod(qApp, [self, alive, done, path] {
            if (!self)
                return;
            if (!done) {
                self->setError(tr("The book could not be shared."));
                return;
            }
            QString shown = path;
            const QString home = QDir::homePath();
            if (shown.startsWith(home + "/"))
                shown = "~" + shown.mid(home.size());
            emit self->shared(path, shown);
        }, Qt::QueuedConnection);
    });
}

void Backend::chooseFiles() {
    if (!m_picker) {
        setError(tr("The desktop's file chooser is not available."));
        return;
    }
    m_picker->openBooks();
}

void Backend::addFiles(const QList<QUrl> &urls) {
    setError({});
    for (const QUrl &url : urls) {
        const QFileInfo source(url.toLocalFile());
        const QString format = source.suffix().toLower();
        if (!source.isFile() || !bookFormats.contains(format)) {
            setError(tr("Only PDF and EPUB files can go on the shelf."));
            continue;
        }

        const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString folder = m_root + "/books/" + id;
        QJsonObject json;
        json["title"] = titleFrom(source.fileName()).isEmpty() ? tr("Untitled") : titleFrom(source.fileName());
        json["author"] = "";
        json["kind"] = "file";
        json["format"] = format;
        json["file"] = "book." + format;
        json["created"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);

        ++m_copying;
        if (m_copying == 1)
            emit busyChanged();

        // A book can be hundreds of megabytes, so the copy runs on a worker.
        // The locker keeps the app alive, windowless if need be, until the
        // copy is done, so closing the window never leaves half a book.
        auto alive = std::make_shared<QEventLoopLocker>();
        QPointer<Backend> self(this);
        const QString from = source.absoluteFilePath();
        const QByteArray description = QJsonDocument(json).toJson();
        QThreadPool::globalInstance()->start([self, alive, id, folder, from, format, description] {
            // The copy is written beside the description last, so a shelf
            // read mid-copy never lists a book whose file isn't whole yet.
            const bool copied = QDir().mkpath(folder)
                                && QFile::copy(from, folder + "/book." + format)
                                && save(folder + "/book.json", description);
            if (!copied)
                QDir(folder).removeRecursively();
            QMetaObject::invokeMethod(qApp, [self, alive, id, copied] {
                if (!self)
                    return;
                if (copied) {
                    self->load();
                    emit self->added(id);
                } else {
                    self->setError(tr("The book could not be added to the shelf."));
                }
                --self->m_copying;
                if (self->m_copying == 0)
                    emit self->busyChanged();
            }, Qt::QueuedConnection);
        });
    }
}

QString Backend::readText(const QString &id) {
    const QString path = textPath(id);
    QFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        setError(tr("The book could not be opened."));
        return {};
    }
    setError({});
    return QString::fromUtf8(file.readAll());
}

bool Backend::saveText(const QString &id, const QString &text) {
    const QString path = textPath(id);
    if (path.isEmpty() || !save(path, text.toUtf8())) {
        setError(tr("The book could not be saved."));
        return false;
    }
    setError({});
    return true;
}

QString Backend::rawText(const QTextDocument &document) {
    QString text = document.toRawText();
    text.replace(QChar::ParagraphSeparator, QChar('\n'));
    return text;
}

bool Backend::saveDocument(const QString &id, QQuickTextDocument *document) {
    if (!document || !document->textDocument()) {
        setError(tr("The book could not be saved."));
        return false;
    }
    return saveText(id, rawText(*document->textDocument()));
}
