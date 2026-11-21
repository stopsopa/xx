use std::collections::VecDeque;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;

use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

use crate::model::Command;
use crate::range::range;

const REVERSE: &str = "\x1b[7m";
const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const RED: &str = "\x1b[31m";
const GREEN: &str = "\x1b[32m";
const CYAN: &str = "\x1b[36m";
const HIDE_CURSOR: &str = "\x1b[?25l";
const SHOW_CURSOR: &str = "\x1b[?25h";

const MESSAGE: &str = "Select command to run";
const HELP: &str = "↑↓ navigate • ⏎ select • type to filter";

#[derive(Debug, Clone, PartialEq)]
pub enum Key {
    Up,
    Down,
    Home,
    End,
    PgUp,
    PgDn,
    Enter,
    Esc,
    CtrlC,
    Backspace,
    Char(char),
    // nothing more to read (terminal closed, or scripted keys ran out)
    Eof,
    Other,
}

/**
 * Where keys come from and where the menu is drawn.
 * Two implementations: real terminal (/dev/tty) and scripted one used by tests.
 */
pub trait Term {
    fn read_key(&mut self) -> Key;
    fn write(&mut self, text: &str);
    // (columns, rows)
    fn size(&self) -> (usize, usize);
}

/**
 * Real terminal. Works on /dev/tty, not on stdin/stdout, because:
 *   - stdout of xx binary is captured by xx.sh (it carries path of generated script)
 *   - stdin of xx belongs to the final script (echo data | xx command)
 *
 * Raw mode is restored on drop (also when panic unwinds).
 */
pub struct Tty {
    file: File,
    saved: libc::termios,
}

impl Tty {
    pub fn open() -> Result<Tty, String> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/tty")
            .map_err(|e| format!("can't open /dev/tty: {e}"))?;

        let fd = file.as_raw_fd();

        // SAFETY: plain termios calls on a file descriptor we own, struct is fully written by tcgetattr
        let saved = unsafe {
            let mut t: libc::termios = std::mem::zeroed();
            if libc::tcgetattr(fd, &mut t) != 0 {
                return Err("tcgetattr on /dev/tty failed".to_string());
            }
            let saved = t;
            libc::cfmakeraw(&mut t);
            t.c_cc[libc::VMIN] = 1;
            t.c_cc[libc::VTIME] = 0;
            if libc::tcsetattr(fd, libc::TCSADRAIN, &t) != 0 {
                return Err("tcsetattr on /dev/tty failed".to_string());
            }
            saved
        };

        let mut tty = Tty { file, saved };
        tty.write(HIDE_CURSOR);
        Ok(tty)
    }

    fn byte(&mut self) -> Option<u8> {
        let mut b = [0u8; 1];
        match self.file.read(&mut b) {
            Ok(1) => Some(b[0]),
            _ => None,
        }
    }

    // is there another byte waiting? used to tell lone Esc from escape sequence
    fn pending(&self, ms: i32) -> bool {
        let mut fds = libc::pollfd {
            fd: self.file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one valid pollfd struct
        unsafe { libc::poll(&mut fds, 1, ms) > 0 }
    }
}

impl Drop for Tty {
    fn drop(&mut self) {
        self.write(SHOW_CURSOR);
        // SAFETY: restoring attributes saved in open()
        unsafe {
            libc::tcsetattr(self.file.as_raw_fd(), libc::TCSADRAIN, &self.saved);
        }
    }
}

impl Term for Tty {
    fn read_key(&mut self) -> Key {
        let b = match self.byte() {
            Some(b) => b,
            None => return Key::Eof,
        };
        match b {
            0x03 => Key::CtrlC,
            // ctrl+d
            0x04 => Key::Esc,
            b'\r' | b'\n' => Key::Enter,
            0x7f | 0x08 => Key::Backspace,
            0x1b => {
                if !self.pending(30) {
                    return Key::Esc;
                }
                let intro = self.byte();
                if intro != Some(b'[') && intro != Some(b'O') {
                    return Key::Other;
                }
                // read parameters until final byte of the sequence
                let mut params = String::new();
                loop {
                    match self.byte() {
                        Some(c) if (0x40..=0x7e).contains(&c) => {
                            return match (c, params.as_str()) {
                                (b'A', _) => Key::Up,
                                (b'B', _) => Key::Down,
                                (b'H', _) => Key::Home,
                                (b'F', _) => Key::End,
                                (b'~', "1") | (b'~', "7") => Key::Home,
                                (b'~', "4") | (b'~', "8") => Key::End,
                                (b'~', "5") => Key::PgUp,
                                (b'~', "6") => Key::PgDn,
                                _ => Key::Other,
                            };
                        }
                        Some(c) => params.push(c as char),
                        None => return Key::Eof,
                    }
                }
            }
            b if b < 0x20 => Key::Other,
            b if b < 0x80 => Key::Char(b as char),
            b => {
                // utf-8: number of following bytes comes from the first byte
                let extra = if b >= 0xf0 {
                    3
                } else if b >= 0xe0 {
                    2
                } else {
                    1
                };
                let mut buf = vec![b];
                for _ in 0..extra {
                    match self.byte() {
                        Some(c) => buf.push(c),
                        None => return Key::Eof,
                    }
                }
                match std::str::from_utf8(&buf)
                    .ok()
                    .and_then(|s| s.chars().next())
                {
                    Some(c) => Key::Char(c),
                    None => Key::Other,
                }
            }
        }
    }

    fn write(&mut self, text: &str) {
        let _ = self.file.write_all(text.as_bytes());
        let _ = self.file.flush();
    }

    fn size(&self) -> (usize, usize) {
        // SAFETY: winsize is plain struct filled by ioctl
        unsafe {
            let mut ws: libc::winsize = std::mem::zeroed();
            if libc::ioctl(self.file.as_raw_fd(), libc::TIOCGWINSZ, &mut ws) == 0
                && ws.ws_col > 0
                && ws.ws_row > 0
            {
                return (ws.ws_col as usize, ws.ws_row as usize);
            }
        }
        (80, 24)
    }
}

/**
 * Terminal for tests, no real terminal needed:
 *
 *   XX_TEST_KEYS="down,down,enter"   keys to "press", comma separated:
 *                                    up down home end pgup pgdn enter esc ctrlc backspace
 *                                    anything else is typed character by character (y, n, abc)
 *   XX_TEST_SIZE="80x24"             optional terminal size
 *
 * Everything what would be drawn goes to stderr. When keys run out it behaves like cancel.
 */
pub struct Scripted {
    keys: VecDeque<Key>,
    size: (usize, usize),
}

impl Scripted {
    pub fn new(spec: &str) -> Scripted {
        let mut keys = VecDeque::new();
        for token in spec.split(',').map(str::trim).filter(|t| !t.is_empty()) {
            match token {
                "up" => keys.push_back(Key::Up),
                "down" => keys.push_back(Key::Down),
                "home" => keys.push_back(Key::Home),
                "end" => keys.push_back(Key::End),
                "pgup" => keys.push_back(Key::PgUp),
                "pgdn" => keys.push_back(Key::PgDn),
                "enter" => keys.push_back(Key::Enter),
                "esc" => keys.push_back(Key::Esc),
                "ctrlc" => keys.push_back(Key::CtrlC),
                "backspace" => keys.push_back(Key::Backspace),
                text => text.chars().for_each(|c| keys.push_back(Key::Char(c))),
            }
        }
        let size = std::env::var("XX_TEST_SIZE")
            .ok()
            .and_then(|s| {
                let (c, r) = s.split_once('x')?;
                Some((c.trim().parse().ok()?, r.trim().parse().ok()?))
            })
            .unwrap_or((80, 24));
        Scripted { keys, size }
    }
}

impl Term for Scripted {
    fn read_key(&mut self) -> Key {
        self.keys.pop_front().unwrap_or(Key::Eof)
    }

    fn write(&mut self, text: &str) {
        eprint!("{text}");
    }

    fn size(&self) -> (usize, usize) {
        self.size
    }
}

/**
 * Picks the terminal: scripted when XX_TEST_KEYS is defined, real /dev/tty otherwise.
 */
pub fn open_term() -> Result<Box<dyn Term>, String> {
    match std::env::var("XX_TEST_KEYS") {
        Ok(spec) => Ok(Box::new(Scripted::new(&spec))),
        Err(_) => Ok(Box::new(Tty::open()?)),
    }
}

// cuts text to given number of terminal columns (emoji and wide characters count as 2)
fn truncate(text: &str, max: usize) -> String {
    if text.width() <= max {
        return text.to_string();
    }
    let mut out = String::new();
    let mut width = 0;
    for c in text.chars() {
        let w = c.width().unwrap_or(0);
        if width + w + 1 > max {
            break;
        }
        out.push(c);
        width += w;
    }
    out.push('…');
    out
}

// text of one row: "█   1 - name"
pub fn label(index: usize, length: usize, name: &str) -> String {
    range(&format!("{:>3} - {}", index + 1, name), index, length)
}

struct Select<'a> {
    list: &'a [Command],
    labels: Vec<String>,
    filter: String,
    // indexes (into list) of rows matching the filter
    visible: Vec<usize>,
    // position in visible
    cursor: usize,
    // first row of visible shown on the screen
    offset: usize,
}

impl<'a> Select<'a> {
    fn new(list: &'a [Command]) -> Select<'a> {
        let labels: Vec<String> = list
            .iter()
            .enumerate()
            .map(|(i, c)| label(i, list.len(), &c.name))
            .collect();
        Select {
            list,
            labels,
            filter: String::new(),
            visible: (0..list.len()).collect(),
            cursor: 0,
            offset: 0,
        }
    }

    // case insensitive "contains" against "<number> - <name>", so typing 12 finds row 12 too
    fn apply_filter(&mut self) {
        let needle = self.filter.to_lowercase();
        self.visible = (0..self.list.len())
            .filter(|&i| {
                needle.is_empty()
                    || format!("{} - {}", i + 1, self.list[i].name)
                        .to_lowercase()
                        .contains(&needle)
            })
            .collect();
        self.cursor = 0;
        self.offset = 0;
    }

    fn selected(&self) -> Option<usize> {
        self.visible.get(self.cursor).copied()
    }

    fn page(&self, rows: usize) -> usize {
        // header + empty line + description + help + one spare line
        rows.saturating_sub(5).max(3)
    }

    fn scroll(&mut self, page: usize) {
        if self.cursor < self.offset {
            self.offset = self.cursor;
        }
        if self.cursor >= self.offset + page {
            self.offset = self.cursor + 1 - page;
        }
    }

    fn lines(&mut self, cols: usize, rows: usize) -> Vec<String> {
        let max = cols.saturating_sub(1).max(10);
        let page = self.page(rows);
        self.scroll(page);

        let mut out = Vec::new();

        let mut header = format!("{GREEN}?{RESET} {BOLD}{MESSAGE}{RESET}");
        if !self.filter.is_empty() {
            header.push_str(&format!(
                " {CYAN}{}{RESET}",
                truncate(&self.filter, max.saturating_sub(MESSAGE.len() + 3))
            ));
        }
        out.push(header);

        if self.visible.is_empty() {
            out.push(format!("  {DIM}(no match){RESET}"));
        }

        for (pos, &i) in self.visible.iter().enumerate().skip(self.offset).take(page) {
            let text = truncate(&self.labels[i], max.saturating_sub(2));
            if pos == self.cursor {
                out.push(format!("❯ {REVERSE}{text}{RESET}"));
            } else {
                out.push(format!("  {text}"));
            }
        }

        out.push(String::new());

        let description = self
            .selected()
            .map(|i| {
                self.list[i]
                    .description
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_default();
        out.push(truncate(&description, max));

        out.push(format!("{DIM}{}{RESET}", truncate(HELP, max)));

        out
    }
}

// replaces what was drawn before (previous number of lines) with new lines
fn draw(term: &mut dyn Term, previous: usize, lines: &[String]) {
    let mut out = String::from("\r");
    if previous > 1 {
        out.push_str(&format!("\x1b[{}A", previous - 1));
    }
    out.push_str("\x1b[J");
    out.push_str(&lines.join("\r\n"));
    term.write(&out);
}

/**
 * Interactive menu. Returns index of selected command, None when cancelled (Esc, Ctrl+C).
 */
pub fn select(term: &mut dyn Term, list: &[Command]) -> Option<usize> {
    let mut state = Select::new(list);
    let mut previous = 0;

    loop {
        let (cols, rows) = term.size();
        let lines = state.lines(cols, rows);
        draw(term, previous, &lines);
        previous = lines.len();

        let count = state.visible.len();
        let page = state.page(rows);

        match term.read_key() {
            Key::Up if count > 0 => state.cursor = (state.cursor + count - 1) % count,
            Key::Down if count > 0 => state.cursor = (state.cursor + 1) % count,
            Key::Home => state.cursor = 0,
            Key::End if count > 0 => state.cursor = count - 1,
            Key::PgUp => state.cursor = state.cursor.saturating_sub(page),
            Key::PgDn if count > 0 => state.cursor = (state.cursor + page).min(count - 1),
            Key::Char(c) => {
                state.filter.push(c);
                state.apply_filter();
            }
            Key::Backspace => {
                state.filter.pop();
                state.apply_filter();
            }
            Key::Enter => {
                if let Some(i) = state.selected() {
                    let (cols, _) = term.size();
                    let text = truncate(
                        &state.labels[i],
                        cols.saturating_sub(MESSAGE.len() + 5).max(10),
                    );
                    draw(
                        term,
                        previous,
                        &[format!(
                            "{GREEN}✔{RESET} {BOLD}{MESSAGE}{RESET} {CYAN}{text}{RESET}\r\n"
                        )],
                    );
                    return Some(i);
                }
            }
            // first Esc clears the filter, second one cancels
            Key::Esc if !state.filter.is_empty() => {
                state.filter.clear();
                state.apply_filter();
            }
            Key::Esc | Key::CtrlC | Key::Eof => {
                draw(term, previous, &[]);
                return None;
            }
            _ => {}
        }
    }
}

/**
 * "Run command?" question. Enter means yes (same default as before).
 * Returns None when cancelled with Ctrl+C.
 */
pub fn confirm(term: &mut dyn Term, name: &str) -> Option<bool> {
    ask(term, "Run command?", name)
}

// the same question with other text, subject is what the question is about (shown in red)
pub fn ask(term: &mut dyn Term, text: &str, subject: &str) -> Option<bool> {
    let (cols, _) = term.size();
    let question = format!(
        "{GREEN}?{RESET} {BOLD}{text}{RESET}     {RED}{}{RESET}   ",
        truncate(subject, cols.saturating_sub(30).max(10))
    );
    term.write(&format!("\r\x1b[K{question}{DIM}(Y/n){RESET} "));

    let answer = loop {
        match term.read_key() {
            Key::Enter | Key::Char('y') | Key::Char('Y') => break Some(true),
            Key::Esc | Key::Char('n') | Key::Char('N') => break Some(false),
            Key::CtrlC | Key::Eof => break None,
            _ => {}
        }
    };

    let text = match answer {
        Some(true) => "yes",
        Some(false) => "no",
        None => "",
    };
    term.write(&format!("\r\x1b[K{question}{CYAN}{text}{RESET}\r\n"));

    answer
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cmd(name: &str) -> Command {
        Command {
            name: name.to_string(),
            command: String::new(),
            description: format!("desc {name}"),
            confirm: None,
            source: false,
            order: None,
        }
    }

    #[test]
    fn truncate_counts_wide_characters() {
        assert_eq!(truncate("abcdef", 10), "abcdef");
        assert_eq!(truncate("abcdef", 4), "abc…");
        assert_eq!(truncate("🚀🚀🚀", 5), "🚀🚀…");
    }

    #[test]
    fn only_selected_row_is_reversed() {
        let list = vec![cmd("a"), cmd("b"), cmd("c")];
        let mut s = Select::new(&list);
        s.cursor = 1;
        let lines = s.lines(80, 24);
        assert_eq!(lines.iter().filter(|l| l.contains(REVERSE)).count(), 1);
        assert!(
            lines[2].starts_with("❯ ") && lines[2].contains("2 - b"),
            "{:?}",
            lines
        );
        assert!(lines.contains(&"desc b".to_string()));
    }

    #[test]
    fn filter_by_name_and_number() {
        let list: Vec<Command> = (1..=12).map(|i| cmd(&format!("cmd{i}"))).collect();
        let mut s = Select::new(&list);
        s.filter = "12".to_string();
        s.apply_filter();
        assert_eq!(s.visible, vec![11]);
        s.filter = "CMD3".to_string();
        s.apply_filter();
        assert_eq!(s.visible, vec![2]);
    }

    #[test]
    fn window_follows_cursor() {
        let list: Vec<Command> = (1..=50).map(|i| cmd(&format!("c{i}"))).collect();
        let mut s = Select::new(&list);
        s.cursor = 49;
        let lines = s.lines(80, 10);
        // 10 rows -> page of 5 rows + header + empty + description + help
        assert_eq!(lines.len(), 9);
        assert!(lines[5].contains("50 - c50"), "{:?}", lines);
    }
}
