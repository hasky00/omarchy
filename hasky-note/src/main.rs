// Hasky Note - a fast terminal note app for Omarchy.
// Notes are plain markdown files in ~/notes (or $HASKY_NOTE_DIR).

use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::Command,
    time::SystemTime,
};

use chrono::Local;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    prelude::*,
    widgets::{Block, BorderType, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

const INBOX: &str = "inbox.md";

fn notes_dir() -> PathBuf {
    let dir = env::var("HASKY_NOTE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| dirs::home_dir().expect("no home dir").join("notes"));
    fs::create_dir_all(&dir).expect("could not create notes dir");
    dir
}

/// Append a timestamped line to inbox.md, under a heading for today.
fn quick_capture(dir: &Path, text: &str) -> io::Result<()> {
    let path = dir.join(INBOX);
    let existing = fs::read_to_string(&path).unwrap_or_default();
    let now = Local::now();
    let heading = format!("## {}", now.format("%Y-%m-%d"));
    let mut out = String::new();
    if existing.is_empty() {
        out.push_str("# Inbox\n");
    }
    if !existing.contains(&heading) {
        out.push_str(&format!("\n{heading}\n"));
    }
    out.push_str(&format!("- {} {}\n", now.format("%H:%M"), text.trim()));
    let mut f = fs::OpenOptions::new().create(true).append(true).open(path)?;
    f.write_all(out.as_bytes())
}

fn slugify(title: &str) -> String {
    let s: String = title
        .trim()
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect();
    let s = s.split('-').filter(|p| !p.is_empty()).collect::<Vec<_>>().join("-");
    if s.is_empty() { Local::now().format("note-%Y%m%d-%H%M%S").to_string() } else { s }
}

struct Note {
    path: PathBuf,
    name: String,
    modified: SystemTime,
    body: String,
}

fn load_notes(dir: &Path) -> Vec<Note> {
    let mut notes: Vec<Note> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().extension().map(|x| x == "md").unwrap_or(false))
        .filter_map(|e| {
            let path = e.path();
            let modified = e.metadata().ok()?.modified().ok()?;
            let body = fs::read_to_string(&path).unwrap_or_default();
            let name = path.file_stem()?.to_string_lossy().to_string();
            Some(Note { path, name, modified, body })
        })
        .collect();
    notes.sort_by(|a, b| b.modified.cmp(&a.modified));
    notes
}

#[derive(PartialEq)]
enum Mode {
    Browse,
    Search,
    NewNote,
    Capture,
    ConfirmDelete,
}

struct App {
    dir: PathBuf,
    notes: Vec<Note>,
    visible: Vec<usize>,
    state: ListState,
    mode: Mode,
    input: String,
    query: String,
    status: String,
}

impl App {
    fn new(dir: PathBuf) -> Self {
        let mut app = App {
            dir,
            notes: vec![],
            visible: vec![],
            state: ListState::default(),
            mode: Mode::Browse,
            input: String::new(),
            query: String::new(),
            status: String::new(),
        };
        app.reload();
        app
    }

    fn reload(&mut self) {
        self.notes = load_notes(&self.dir);
        self.filter();
    }

    fn filter(&mut self) {
        let q = self.query.to_lowercase();
        self.visible = (0..self.notes.len())
            .filter(|&i| {
                q.is_empty()
                    || self.notes[i].name.to_lowercase().contains(&q)
                    || self.notes[i].body.to_lowercase().contains(&q)
            })
            .collect();
        let sel = self.state.selected().unwrap_or(0).min(self.visible.len().saturating_sub(1));
        self.state.select(if self.visible.is_empty() { None } else { Some(sel) });
    }

    fn selected(&self) -> Option<&Note> {
        self.state.selected().and_then(|i| self.visible.get(i)).map(|&i| &self.notes[i])
    }

    fn move_by(&mut self, d: i32) {
        if self.visible.is_empty() {
            return;
        }
        let n = self.visible.len() as i32;
        let i = self.state.selected().unwrap_or(0) as i32;
        self.state.select(Some(((i + d).rem_euclid(n)) as usize));
    }
}

type Term = Terminal<CrosstermBackend<io::Stdout>>;

fn setup() -> io::Result<Term> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)?;
    Terminal::new(CrosstermBackend::new(io::stdout()))
}

fn restore() -> io::Result<()> {
    disable_raw_mode()?;
    execute!(io::stdout(), LeaveAlternateScreen)
}

/// Leave the TUI, open a file in $EDITOR (nvim on Omarchy), then come back.
fn edit(term: &mut Term, path: &Path) -> io::Result<()> {
    restore()?;
    let editor = env::var("EDITOR").unwrap_or_else(|_| "nvim".into());
    let _ = Command::new(editor).arg(path).status();
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)?;
    term.clear()
}

fn ui(f: &mut Frame, app: &mut App) {
    let [main, bar] =
        Layout::vertical([Constraint::Min(1), Constraint::Length(1)]).areas(f.area());
    let [left, right] =
        Layout::horizontal([Constraint::Percentage(32), Constraint::Percentage(68)]).areas(main);

    // Uses plain ANSI colors, so the active Omarchy theme colors it automatically.
    let title = if app.query.is_empty() {
        format!(" Hasky Note ({}) ", app.visible.len())
    } else {
        format!(" /{} ({}) ", app.query, app.visible.len())
    };
    let items: Vec<ListItem> = app
        .visible
        .iter()
        .map(|&i| ListItem::new(app.notes[i].name.clone()))
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(Color::Blue))
                .title(title),
        )
        .highlight_style(Style::default().fg(Color::Black).bg(Color::Blue).bold())
        .highlight_symbol("> ");
    f.render_stateful_widget(list, left, &mut app.state);

    let (ptitle, body) = match app.selected() {
        Some(n) => (format!(" {} ", n.name), n.body.clone()),
        None => (" empty ".into(), "No notes yet. Press n to make one, or c to capture a thought.".into()),
    };
    let preview = Paragraph::new(body)
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(Color::DarkGray))
                .title(ptitle),
        );
    f.render_widget(preview, right);

    let line = match app.mode {
        Mode::Browse if !app.status.is_empty() => Line::from(app.status.clone()).green(),
        Mode::Browse => Line::from(
            " enter edit  n new  c capture  / search  d delete  r reload  q quit",
        )
        .dark_gray(),
        Mode::Search => Line::from(format!(" search: {}_", app.input)).yellow(),
        Mode::NewNote => Line::from(format!(" new note title: {}_", app.input)).yellow(),
        Mode::Capture => Line::from(format!(" capture: {}_", app.input)).yellow(),
        Mode::ConfirmDelete => Line::from(" move this note to .trash? y/n").red(),
    };
    f.render_widget(Paragraph::new(line), bar);
}

fn run(term: &mut Term, app: &mut App) -> io::Result<()> {
    loop {
        term.draw(|f| ui(f, app))?;
        let Event::Key(key) = event::read()? else { continue };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(());
        }

        match app.mode {
            Mode::Browse => {
                app.status.clear();
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Char('j') | KeyCode::Down => app.move_by(1),
                    KeyCode::Char('k') | KeyCode::Up => app.move_by(-1),
                    KeyCode::Char('g') => app.state.select(Some(0)),
                    KeyCode::Char('r') => app.reload(),
                    KeyCode::Char('/') => {
                        app.input = app.query.clone();
                        app.mode = Mode::Search;
                    }
                    KeyCode::Char('n') => {
                        app.input.clear();
                        app.mode = Mode::NewNote;
                    }
                    KeyCode::Char('c') => {
                        app.input.clear();
                        app.mode = Mode::Capture;
                    }
                    KeyCode::Char('d') if app.selected().is_some() => {
                        app.mode = Mode::ConfirmDelete
                    }
                    KeyCode::Enter | KeyCode::Char('e') => {
                        if let Some(p) = app.selected().map(|n| n.path.clone()) {
                            edit(term, &p)?;
                            app.reload();
                        }
                    }
                    _ => {}
                }
            }
            Mode::ConfirmDelete => {
                if key.code == KeyCode::Char('y') {
                    if let Some(p) = app.selected().map(|n| n.path.clone()) {
                        let trash = app.dir.join(".trash");
                        fs::create_dir_all(&trash)?;
                        let stamp = Local::now().format("%Y%m%d-%H%M%S");
                        let name = p.file_name().unwrap().to_string_lossy();
                        fs::rename(&p, trash.join(format!("{stamp}-{name}")))?;
                        app.status = " moved to ~/notes/.trash".into();
                        app.reload();
                    }
                }
                app.mode = Mode::Browse;
            }
            Mode::Search | Mode::NewNote | Mode::Capture => match key.code {
                KeyCode::Esc => {
                    if app.mode == Mode::Search {
                        app.query.clear();
                        app.filter();
                    }
                    app.mode = Mode::Browse;
                }
                KeyCode::Backspace => {
                    app.input.pop();
                    if app.mode == Mode::Search {
                        app.query = app.input.clone();
                        app.filter();
                    }
                }
                KeyCode::Char(c) => {
                    app.input.push(c);
                    if app.mode == Mode::Search {
                        app.query = app.input.clone();
                        app.filter();
                    }
                }
                KeyCode::Enter => {
                    let text = app.input.trim().to_string();
                    match app.mode {
                        Mode::NewNote if !text.is_empty() => {
                            let mut path = app.dir.join(format!("{}.md", slugify(&text)));
                            let mut i = 2;
                            while path.exists() {
                                path = app.dir.join(format!("{}-{i}.md", slugify(&text)));
                                i += 1;
                            }
                            fs::write(&path, format!("# {text}\n\n"))?;
                            edit(term, &path)?;
                            app.query.clear();
                            app.reload();
                            app.state.select(Some(0));
                        }
                        Mode::Capture if !text.is_empty() => {
                            quick_capture(&app.dir, &text)?;
                            app.status = " saved to inbox".into();
                            app.reload();
                        }
                        _ => {}
                    }
                    app.mode = Mode::Browse;
                }
                _ => {}
            },
        }
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    let dir = notes_dir();

    match args.first().map(String::as_str) {
        Some("-h") | Some("--help") => {
            println!(
                "hasky-note - fast terminal notes for Omarchy\n\n\
                 usage:\n  hasky-note              open the note browser\n  \
                 hasky-note <text...>    quick capture to inbox.md\n\n\
                 notes folder: {}",
                dir.display()
            );
            Ok(())
        }
        Some(_) => {
            quick_capture(&dir, &args.join(" "))?;
            println!("saved to {}", dir.join(INBOX).display());
            Ok(())
        }
        None => {
            let mut term = setup()?;
            let mut app = App::new(dir);
            let res = run(&mut term, &mut app);
            restore()?;
            res
        }
    }
}
