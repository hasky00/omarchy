import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 960
    height: 680
    minimumWidth: 640
    minimumHeight: 460
    visible: true
    title: "Hasky Shelf"
    color: theme.background

    Material.theme: theme.light ? Material.Light : Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.foreground

    readonly property bool rightToLeft: Qt.application.layoutDirection === Qt.RightToLeft
    // Bare keys belong to the shelf, so they step aside whenever a dialog,
    // and the text fields in it, has the keyboard.
    readonly property bool shelfHasKeys: !newBook.opened && !help.opened && !editing

    // The book open for writing, by its id; none while the shelf is showing.
    property string openId: ""
    property string openTitle: ""
    property string openAuthor: ""
    readonly property bool editing: openId !== ""

    // One cell of the shelf: a cover standing on a lit shelf line.
    readonly property int cellWidth: 168
    readonly property int cellHeight: 262
    readonly property int coverWidth: 128
    readonly property int coverHeight: 184
    // Where the shelf line sits inside a cell, just under the cover's foot.
    readonly property int shelfLine: 218

    // Covers take their colors from the theme's palette, so the shelf changes
    // with the theme like the rest of the desktop.
    readonly property var palette: [
        theme.colors.blue, theme.colors.magenta, theme.colors.cyan,
        theme.colors.green, theme.colors.yellow, theme.colors.red
    ]

    function tintFor(index) {
        const picked = palette[index % palette.length]
        return picked ? picked : theme.accent
    }

    // Covers are panels of tinted glass: mostly the window's own background,
    // with enough of the book's color to tell them apart, so the title reads
    // in the theme's foreground on a light theme as well as a dark one.
    function glass(color, amount) {
        const base = theme.background
        return Qt.rgba(base.r + (color.r - base.r) * amount,
                       base.g + (color.g - base.g) * amount,
                       base.b + (color.b - base.b) * amount, 1)
    }

    function fade(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function openBook(index) {
        const book = backend.books[index]
        if (!book)
            return
        // A book added from a file opens in the desktop's reader for it.
        if (book.kind === "file") {
            backend.openInReader(book.id)
            return
        }
        const text = backend.readText(book.id)
        if (backend.error !== "")
            return
        page.text = text
        page.savedText = page.text
        page.written = false
        page.cursorPosition = page.length
        win.countWords()
        openTitle = book.title
        openAuthor = book.author
        openId = book.id
        page.forceActiveFocus()
    }

    // True when nothing is left unsaved, so leaving the book loses nothing.
    function saveBook() {
        if (!editing || !page.unsaved)
            return true
        if (!backend.saveDocument(openId, page.textDocument))
            return false
        page.savedText = page.text
        win.countWords()
        return true
    }

    function closeBook() {
        if (!saveBook())
            return
        // Escape saves and leaves in one step, so the page's own "Saved"
        // is gone before it can be read; the shelf says it instead.
        if (page.written) {
            say(qsTr("Saved"), 3000)
        }
        openId = ""
        grid.forceActiveFocus()
    }

    function shareBook(index) {
        const book = backend.books[index]
        if (book)
            backend.shareBook(book.id)
    }

    function say(words, time) {
        notice = words
        noticeTimer.interval = time
        noticeTimer.restart()
    }

    // A short word on the shelf about what just happened, cleared again
    // a moment later.
    property string notice: ""
    Timer {
        id: noticeTimer
        interval: 3000
        onTriggered: win.notice = ""
    }

    property int words: 0
    function countWords() {
        const found = page.text.trim()
        words = found === "" ? 0 : found.split(/\s+/).length
    }

    // A book that can't be saved keeps the window open, with the reason shown.
    onClosing: function(close) { close.accepted = saveBook() }

    // On the shelf the keys are bare; in a book they are text, so the
    // shortcuts move to F1, Escape and Ctrl.
    Shortcut { sequence: "?"; enabled: !newBook.opened && !win.editing; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Q"; enabled: win.shelfHasKeys; onActivated: Qt.quit() }
    Shortcut { sequence: "N"; enabled: win.shelfHasKeys; onActivated: newBook.open() }
    Shortcut { sequence: "A"; enabled: win.shelfHasKeys; onActivated: backend.chooseFiles() }
    Shortcut { sequence: "S"; enabled: win.shelfHasKeys; onActivated: win.shareBook(grid.currentIndex) }
    // One Shortcut per key, so `omarchy agent look app --keys` can press each.
    Shortcut { sequence: "Return"; enabled: win.shelfHasKeys; onActivated: win.openBook(grid.currentIndex) }
    Shortcut { sequence: "Enter"; enabled: win.shelfHasKeys; onActivated: win.openBook(grid.currentIndex) }

    Shortcut { sequence: "F1"; enabled: win.editing; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Ctrl+?"; enabled: win.editing; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Escape"; enabled: win.editing && !help.opened; onActivated: win.closeBook() }
    Shortcut { sequences: [StandardKey.Save]; enabled: win.editing; onActivated: win.saveBook() }
    Shortcut { sequence: "Ctrl+Q"; enabled: win.editing; onActivated: if (win.saveBook()) Qt.quit() }

    // A book that has just been added is the one picked on the shelf.
    Connections {
        target: backend
        function onAdded(id) {
            for (let i = 0; i < backend.books.length; ++i) {
                if (backend.books[i].id === id)
                    grid.currentIndex = i
            }
        }
        // A path takes longer to read than a word.
        function onShared(path, shown) {
            win.say(qsTr("Copy saved as %1").arg(shown), 8000)
        }
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        visible: !win.editing
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        RowLayout {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 16

            Label {
                objectName: "bookCount"
                text: qsTr("%Ln books", "", backend.books.length)
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 1.5
                font.capitalization: Font.AllUppercase
                color: theme.accent
            }

            Label {
                objectName: "notice"
                visible: win.notice !== "" && !backend.busy
                text: win.notice
                opacity: 0.7
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            Label {
                objectName: "adding"
                visible: backend.busy
                text: qsTr("Adding…")
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { keys: "↵", action: qsTr("Open") },
                    { keys: "N", action: qsTr("New book") },
                    { keys: "A", action: qsTr("Add files") },
                    { keys: "S", action: qsTr("Share") },
                    { keys: "?", action: qsTr("Shortcuts") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: 8

                    Label {
                        text: modelData.keys
                        color: theme.accent
                        font.bold: true
                    }
                    Label {
                        text: modelData.action
                        opacity: 0.7
                    }
                }
            }
        }

        Label {
            objectName: "error"
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            visible: backend.error !== ""
            text: backend.error
            color: theme.colors.red ? theme.colors.red : theme.accent
            wrapMode: Text.Wrap
        }

        Item {
            id: shelfArea
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 28
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            clip: true

            // The cabinet's own woodwork: side walls, and the hood that holds
            // the light above the top shelf.
            readonly property int wall: 12
            readonly property int hood: 34
            readonly property int board: 8

            readonly property int columns: Math.max(1, Math.floor((width - 2 * wall - 32) / win.cellWidth))
            readonly property int rows: Math.max(Math.ceil(backend.books.length / columns),
                                                 Math.ceil(grid.height / win.cellHeight))

            Rectangle {
                id: cabinet
                objectName: "cabinet"
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: grid.width + 2 * shelfArea.wall + 32
                radius: theme.radius
                // The back panel, a shade off the wall behind the cabinet.
                color: win.glass(theme.foreground, 0.04)
                border.width: 1
                border.color: win.fade(theme.foreground, 0.22)
                clip: true

                // The boards run wall to wall whether or not a book stands on
                // them, and travel with the books as the shelf scrolls.
                Repeater {
                    model: shelfArea.rows
                    delegate: Item {
                        required property int index
                        x: shelfArea.wall
                        width: cabinet.width - 2 * shelfArea.wall
                        y: shelfArea.hood + index * win.cellHeight + win.shelfLine - grid.contentY

                        Rectangle {
                            width: parent.width
                            height: shelfArea.board
                            color: win.glass(theme.foreground, 0.16)
                        }
                        // The board's front edge, catching the light from above.
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: win.fade(theme.accent, 0.9)
                        }
                        // And the shadow it throws on the shelf below.
                        Rectangle {
                            y: shelfArea.board
                            width: parent.width
                            height: 22
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, theme.light ? 0.10 : 0.35) }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                            }
                        }
                    }
                }

                // The hood, with the neon tube under it.
                Rectangle {
                    width: parent.width
                    height: shelfArea.hood - 12
                    color: win.glass(theme.foreground, 0.12)
                }
                Rectangle {
                    id: neon
                    objectName: "neon"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: shelfArea.hood - 12
                    width: parent.width - 2 * shelfArea.wall - 24
                    height: 6
                    radius: 3
                    color: theme.accent
                }
                // Its hot core.
                Rectangle {
                    anchors.horizontalCenter: neon.horizontalCenter
                    y: neon.y + 2
                    width: neon.width - 10
                    height: 2
                    radius: 1
                    color: Qt.lighter(theme.accent, 1.6)
                }
                // And the light it pours down the cabinet.
                Rectangle {
                    x: shelfArea.wall
                    y: neon.y + neon.height
                    width: parent.width - 2 * shelfArea.wall
                    height: 150
                    gradient: Gradient {
                        GradientStop { position: 0; color: win.fade(theme.accent, 0.30) }
                        GradientStop { position: 0.35; color: win.fade(theme.accent, 0.10) }
                        GradientStop { position: 1; color: win.fade(theme.accent, 0) }
                    }
                }

                // The side walls stand in front of the boards.
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        required property int index
                        x: index === 0 ? 0 : cabinet.width - shelfArea.wall
                        width: shelfArea.wall
                        height: cabinet.height
                        color: win.glass(theme.foreground, 0.12)
                        border.width: 1
                        border.color: win.fade(theme.foreground, 0.18)
                    }
                }
            }

            GridView {
                id: grid
                objectName: "shelf"
                anchors.top: cabinet.top
                anchors.topMargin: shelfArea.hood
                anchors.bottom: cabinet.bottom
                anchors.bottomMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: shelfArea.columns * win.cellWidth
                clip: true
                cellWidth: win.cellWidth
                cellHeight: win.cellHeight
                model: backend.books
                focus: true
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                layoutDirection: win.rightToLeft ? Qt.RightToLeft : Qt.LeftToRight

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: win.cellWidth
                    height: win.cellHeight

                    readonly property bool current: GridView.isCurrentItem
                    readonly property color tint: win.tintFor(modelData.tint)

                    // The book's color, thrown onto the board it stands on.
                    Rectangle {
                        anchors.horizontalCenter: cover.horizontalCenter
                        y: win.shelfLine + 1
                        width: win.coverWidth
                        height: 7
                        color: win.fade(cell.tint, cell.current ? 0.75 : 0.35)
                    }

                    Rectangle {
                        id: cover
                        objectName: "cover"
                        anchors.horizontalCenter: parent.horizontalCenter
                        // A picked book lifts off the shelf and lights up.
                        y: win.shelfLine - win.coverHeight - (cell.current ? 14 : 2)
                        width: win.coverWidth
                        height: win.coverHeight
                        radius: Math.min(4, theme.radius)
                        border.width: cell.current ? 2 : 1
                        border.color: cell.current ? cell.tint : win.fade(cell.tint, 0.55)
                        gradient: Gradient {
                            GradientStop { position: 0; color: win.glass(cell.tint, cell.current ? 0.30 : 0.14) }
                            GradientStop { position: 1; color: win.glass(cell.tint, cell.current ? 0.46 : 0.26) }
                        }

                        Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        // A lit strip along the top edge, in the book's color.
                        Rectangle {
                            x: 1
                            y: 1
                            width: parent.width - 2
                            height: 4
                            color: cell.tint
                        }

                        // The spine, as a hairline of the same light.
                        Rectangle {
                            x: 9
                            y: 5
                            width: 1
                            height: parent.height - 6
                            color: win.fade(cell.tint, 0.5)
                        }

                        Label {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 20
                            anchors.leftMargin: 20
                            anchors.rightMargin: 12
                            text: cell.modelData.title
                            color: theme.foreground
                            font.pixelSize: 15
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // The book's place on the shelf, like a readout.
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.bottom: author.top
                            anchors.bottomMargin: 6
                            // A book that came from a file says which kind.
                            text: String(cell.index + 1).padStart(2, "0")
                                  + (cell.modelData.kind === "file" ? "  " + cell.modelData.format.toUpperCase() : "")
                            color: cell.tint
                            font.family: "monospace"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Label {
                            id: author
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottomMargin: 14
                            anchors.leftMargin: 20
                            anchors.rightMargin: 10
                            text: cell.modelData.author
                            color: theme.foreground
                            opacity: 0.75
                            font.pixelSize: 10
                            font.letterSpacing: 0.4
                            font.capitalization: Font.AllUppercase
                            // A long name takes a second line before it is cut.
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: cover
                        onClicked: grid.currentIndex = cell.index
                        onDoubleClicked: win.openBook(cell.index)
                    }
                }
            }

            // Files dragged in from the file manager land on the shelf too.
            DropArea {
                anchors.fill: parent
                onDropped: function(drop) {
                    if (drop.hasUrls)
                        backend.addFiles(drop.urls)
                }
            }

            ColumnLayout {
                objectName: "empty"
                anchors.centerIn: parent
                visible: backend.books.length === 0
                spacing: 8

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Your shelf is empty")
                    font.pixelSize: 24
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Press N to write your first book")
                    opacity: 0.7
                }
            }
        }
    }


    // The open book: a page to write on, and nothing else.
    Item {
        id: editorView
        objectName: "editorView"
        anchors.fill: parent
        visible: win.editing
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        RowLayout {
            id: bookHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 16

            Label {
                objectName: "openTitle"
                Layout.maximumWidth: editorView.width * 0.4
                text: win.openTitle
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 1.5
                font.capitalization: Font.AllUppercase
                color: theme.accent
                elide: Text.ElideRight
            }
            Label {
                Layout.maximumWidth: editorView.width * 0.2
                text: win.openAuthor
                opacity: 0.7
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true }

            Label {
                objectName: "saveState"
                text: page.unsaved ? qsTr("Not saved yet") : qsTr("Saved")
                opacity: 0.7
            }
            Label {
                objectName: "wordCount"
                text: qsTr("%Ln words", "", win.words)
                opacity: 0.7
            }
            RowLayout {
                spacing: 8
                Label {
                    text: "Esc"
                    color: theme.accent
                    font.bold: true
                }
                Label {
                    text: qsTr("Shelf")
                    opacity: 0.7
                }
            }
        }

        Label {
            id: bookError
            anchors.top: bookHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            visible: backend.error !== ""
            text: backend.error
            color: theme.colors.red ? theme.colors.red : theme.accent
            wrapMode: Text.Wrap
        }

        // The same neon that lights the cabinet, over the page.
        Rectangle {
            id: pageLight
            anchors.top: bookError.visible ? bookError.bottom : bookHeader.bottom
            anchors.topMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 48, 760)
            height: 2
            color: theme.accent
        }

        Flickable {
            id: pageArea
            anchors.top: pageLight.bottom
            anchors.topMargin: 20
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: pageLight.width
            contentWidth: width
            contentHeight: page.implicitHeight + 120
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            // Keeps the line being written in view as the book grows.
            function follow(cursor) {
                if (cursor.y < contentY)
                    contentY = cursor.y
                else if (cursor.y + cursor.height > contentY + height - 40)
                    contentY = cursor.y + cursor.height - height + 40
            }

            TextEdit {
                id: page
                objectName: "page"
                width: pageArea.width
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                color: theme.foreground
                selectionColor: theme.accent
                selectedTextColor: theme.accentForeground
                font.pixelSize: 17

                // What is on disk, to tell written from saved by comparing
                // the two, so undoing back to the saved text is clean again.
                property string savedText: ""
                readonly property bool unsaved: text !== savedText
                // Whether anything was written since the book was opened.
                property bool written: false

                onCursorRectangleChanged: pageArea.follow(cursorRectangle)
                onTextChanged: {
                    if (win.editing && unsaved) {
                        written = true
                        autosave.restart()
                    }
                }
            }

            Label {
                visible: page.length === 0
                text: qsTr("Start writing…")
                font: page.font
                opacity: 0.4
            }
        }

        // One save a moment after the writer pauses, rather than one per key.
        Timer {
            id: autosave
            interval: 1200
            onTriggered: win.saveBook()
        }
    }

    Popup {
        id: newBook
        objectName: "newBook"
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        padding: 24
        width: Math.min(420, win.width - 48)
        background: Rectangle {
            color: theme.background
            border.color: theme.accent
            radius: theme.radius
        }

        function create() {
            if (backend.createBook(titleField.text, authorField.text) !== "") {
                grid.currentIndex = backend.books.length - 1
                close()
            }
        }

        onOpened: {
            titleField.text = ""
            authorField.text = ""
            titleField.forceActiveFocus()
        }
        onClosed: grid.forceActiveFocus()

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16
            LayoutMirroring.enabled: win.rightToLeft
            LayoutMirroring.childrenInherit: true

            Label {
                text: qsTr("New book")
                font.pixelSize: 20
                font.bold: true
            }

            TextField {
                id: titleField
                objectName: "titleField"
                Layout.fillWidth: true
                placeholderText: qsTr("Title")
                Material.roundedScale: theme.radius
                onAccepted: newBook.create()
            }

            TextField {
                id: authorField
                objectName: "authorField"
                Layout.fillWidth: true
                placeholderText: qsTr("Author")
                Material.roundedScale: theme.radius
                onAccepted: newBook.create()
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                Button {
                    text: qsTr("Cancel")
                    flat: true
                    Material.roundedScale: theme.radius
                    onClicked: newBook.close()
                }
                Button {
                    id: createButton
                    objectName: "createButton"
                    text: qsTr("Create")
                    highlighted: true
                    Material.roundedScale: theme.radius
                    onClicked: newBook.create()
                    // A highlighted button colors its caption by Material's
                    // own rule, so it can't read on every accent.
                    contentItem: Label {
                        text: createButton.text
                        font: createButton.font
                        color: theme.accentForeground
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Popup {
        id: help
        objectName: "help"
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        padding: 24
        background: Rectangle {
            color: theme.background
            border.color: theme.colors.selection
            radius: theme.radius
        }

        ColumnLayout {
            spacing: 8
            // A popup is not an Item and doesn't inherit the window's
            // mirroring, so its content opts in.
            LayoutMirroring.enabled: win.rightToLeft
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: win.editing ? [
                    { keys: "Esc", action: qsTr("Back to the shelf") },
                    { keys: "Ctrl S", action: qsTr("Save now") },
                    { keys: "F1", action: qsTr("Show or hide the shortcuts") },
                    { keys: "Ctrl Q", action: qsTr("Quit") }
                ] : [
                    { keys: "↵", action: qsTr("Open the book") },
                    { keys: "N", action: qsTr("Write a new book") },
                    { keys: "A", action: qsTr("Add PDF or EPUB files") },
                    { keys: "S", action: qsTr("Share the book as a file") },
                    { keys: "← → ↑ ↓", action: qsTr("Move along the shelf") },
                    { keys: "?", action: qsTr("Show or hide the shortcuts") },
                    { keys: "Q", action: qsTr("Quit") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: 24

                    Label {
                        Layout.preferredWidth: 88
                        text: modelData.keys
                        color: theme.accent
                        font.bold: true
                    }
                    Label { text: modelData.action }
                }
            }
        }
    }
}
