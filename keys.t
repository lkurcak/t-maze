//! Keys, read one at a time from the terminal in raw mode. An arrow comes
//! as three bytes, escape, `[` and a letter; escape on its own, with
//! nothing after it for a moment, is the escape key.

use core::io::Read;
use core::time::Duration;
use std::io::{Error, ErrorKind, Raw};
use std::time::Clock;

use crate::maze::Dir;

/// What a key says to do.
#[derive(Copy, Discard, Eq)]
pub enum Key {
    /// Take a step.
    Go(Dir),
    /// Search for the way with the fewest steps: `b`, for breadth first.
    Fewest,
    /// Search for the quickest way: `d`, for Dijkstra.
    Quickest,
    /// A new maze: `n`.
    New,
    /// Stop: `q`, escape, or Ctrl-C.
    Quit,
    Other,
}

/// The next key pressed.
pub fn read(raw: &mut Raw<'_>, clock: Clock) -> Result<Key, Error> {
    Ok(
        match byte(raw)? {
            // Escape: an arrow, if the rest of one comes at once.
            27 => {
                if !raw.wait(clock.now().add(Duration::from_millis(30)))? {
                    return Ok(Key::Quit);
                }
                if byte(raw)? != 91 {
                    return Ok(Key::Other);
                }
                match byte(raw)? {
                    65 => Key::Go(Dir::Up),
                    66 => Key::Go(Dir::Down),
                    67 => Key::Go(Dir::Right),
                    68 => Key::Go(Dir::Left),
                    _ => Key::Other,
                }
            },
            // `k`, `j`, `l` and `h`, as in vi.
            107 => Key::Go(Dir::Up),
            106 => Key::Go(Dir::Down),
            108 => Key::Go(Dir::Right),
            104 => Key::Go(Dir::Left),
            // `b` and `d`.
            98 => Key::Fewest,
            100 => Key::Quickest,
            // `n`.
            110 => Key::New,
            // `q`, or Ctrl-C, which in raw mode is a key like any other.
            113 | 3 => Key::Quit,
            _ => Key::Other,
        },
    )
}

/// The next byte of input.
fn byte(raw: &mut Raw<'_>) -> Result<u8, Error> {
    let mut b = [0u8; 1];
    if raw.read(b.as_mut_slice())? == 0 {
        return Err(Error::new(ErrorKind::UnexpectedEnd));
    }
    Ok(b[0])
}
