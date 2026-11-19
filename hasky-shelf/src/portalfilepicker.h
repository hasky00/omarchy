#pragma once

#include <QVariantMap>

#include "filepicker.h"

class QDBusPendingCallWatcher;

// Adapted from Omacut's src/portalfilepicker.{h,cpp}
// (https://github.com/omacom/omacut), Copyright (c) 2026 David Heinemeier
// Hansson, MIT License; see LICENSE.omacut. It is the picker that survives a
// portal that stops answering or is replaced while its dialog is up.
class PortalFilePicker : public FilePicker {
    Q_OBJECT

public:
    explicit PortalFilePicker(QObject *parent = nullptr);

    void openBooks() override;

private slots:
    void handleResponse(uint response, const QVariantMap &results);

private:
    void requestFile(const QString &method, const QString &title, QVariantMap options);
    bool connectToRequestPath(const QString &path);
    void clearPending();
    // Best-effort Close of the pending portal request, if there is one.
    void closePendingRequest();

    QString m_pendingPath;
    bool m_pending = false;
    // Bumped per request, so a late reply for a replaced request is ignored.
    int m_pendingGeneration = 0;
    QDBusPendingCallWatcher *m_pendingWatcher = nullptr;
};
