#pragma once

#include <QList>
#include <QObject>
#include <QUrl>

// The dialogs the shelf asks the desktop for. Abstract so tests can stand a
// fake in for the portal.
class FilePicker : public QObject {
    Q_OBJECT

public:
    explicit FilePicker(QObject *parent = nullptr) : QObject(parent) {}
    virtual ~FilePicker() = default;

    // Pick one or more book files to put on the shelf.
    virtual void openBooks() = 0;

signals:
    void booksSelected(const QList<QUrl> &urls);
    void failed(const QString &message);
};
