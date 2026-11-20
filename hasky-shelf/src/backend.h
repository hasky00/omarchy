#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

#include <QList>
#include <QUrl>

class FilePicker;
class QQuickTextDocument;
class QTextDocument;

// The shelf: every book is a folder under <root>/books/<id>/ holding a
// book.json that describes it and the book's own content beside it.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList books READ books NOTIFY booksChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    // An empty root means the user's own data folder; tests pass a temp one.
    // The picker is the desktop's file chooser; without one, files still
    // arrive by being dropped on the window.
    explicit Backend(const QString &root = QString(), FilePicker *picker = nullptr, QObject *parent = nullptr);

    QVariantList books() const { return m_books; }
    QString error() const { return m_error; }
    // True while books are being copied onto the shelf.
    bool busy() const { return m_copying > 0; }
    QString root() const { return m_root; }

    // Returns the new book's id, or an empty string when it could not be saved.
    Q_INVOKABLE QString createBook(const QString &title, const QString &author);

    // The text of a book written here. An unknown book reads as empty and
    // sets the error.
    Q_INVOKABLE QString readText(const QString &id);
    Q_INVOKABLE bool saveText(const QString &id, const QString &text);
    // What the editor calls: saves the document's own characters, not the
    // flattened copy a text property hands out.
    Q_INVOKABLE bool saveDocument(const QString &id, QQuickTextDocument *document);

    // Asks the desktop for book files, and puts the chosen ones on the shelf.
    Q_INVOKABLE void chooseFiles();
    // Copies each PDF or EPUB onto the shelf. The originals are only read.
    // The copying happens off the GUI thread; added() follows each book.
    Q_INVOKABLE void addFiles(const QList<QUrl> &urls);
    // Where a book added from a file keeps its copy, or an empty string.
    Q_INVOKABLE QString filePath(const QString &id) const;
    // Opens such a book in the desktop's own reader for its format.
    Q_INVOKABLE bool openInReader(const QString &id);

    // Puts a copy of the book in the share folder as one file to hand to
    // someone: an EPUB of a book written here, the file itself of one that
    // was added. shared() follows with where it went. The book on the shelf
    // must be saved first; the copy is made from what is on disk.
    Q_INVOKABLE void shareBook(const QString &id);
    // Where shared copies go: the user's Documents unless a test says otherwise.
    void setShareFolder(const QString &folder) { m_shareFolder = folder; }

    // A document's text as it should be written to disk: only the paragraph
    // separators become newlines, so a non-breaking space the writer typed
    // is still one when the book is opened again.
    static QString rawText(const QTextDocument &document);

signals:
    void booksChanged();
    void errorChanged();
    void busyChanged();
    void added(const QString &id);
    // path is the new file; shown is the same with the home folder as ~.
    void shared(const QString &path, const QString &shown);

private:
    void load();
    // The book's content file, or an empty string when the shelf has no such
    // written book. An id is only ever matched against the shelf, never
    // turned into a path on its own.
    QString textPath(const QString &id) const;
    QVariantMap book(const QString &id) const;
    void setError(const QString &error);

    QString m_root;
    QString m_shareFolder;
    QVariantList m_books;
    QString m_error;
    FilePicker *m_picker;
    int m_copying = 0;
};
