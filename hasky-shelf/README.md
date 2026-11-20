# Hasky Shelf

A shelf for the books you write and collect, for Omarchy. Books stand cover-out in a cabinet lit by a neon tube that takes the color of your theme.

- Write a book: press `N`, give it a title, and open it with `Enter` to write. It saves by itself as you go.
- Add a book you already have: press `A`, or drag PDF and EPUB files onto the window. Each is copied onto the shelf; the original is never changed.
- Open a book you added with `Enter`, and it opens in your desktop's own reader.
- Share a book: press `S`, and a copy lands in your Documents folder as one file. A book you wrote becomes an EPUB that any reader app opens and any other Hasky Shelf can take in with `A`; a book you added is copied as the file it is. A copy shared before is never written over.

Your books live in `~/.local/share/haskyshelf/books/`, one folder each.

## Shortcuts

On the shelf:

| Key | Action |
| --- | --- |
| `Enter` | Open the book |
| `N` | Write a new book |
| `A` | Add PDF or EPUB files |
| `S` | Share the book as a file |
| Arrow keys | Move along the shelf |
| `?` | Show or hide the shortcuts |
| `Q` | Quit |

In a book:

| Key | Action |
| --- | --- |
| `Esc` | Back to the shelf |
| `Ctrl S` | Save now |
| `F1` | Show or hide the shortcuts |
| `Ctrl Q` | Quit |

## Building

```bash
bin/build
bin/test
cmake --install build --prefix ~/.local
```

On Hasky Omarchy, pick **Install > Hasky Labs > Hasky Shelf** in the Omarchy menu instead.

Made by Hasky Labs, Copenhagen. MIT licensed; the file chooser is adapted from Omacut, see `LICENSE.omacut`.
