/*!
 * Port of pages/bash/xx/lib/range.js
 *
 * Adds one block character in front of each menu row. Blocks are thick at both ends
 * of the list and thin in the middle, which gives visual hint where in the list we are.
 */

// █ ▉ ▊ ▋ ▌ ▍ ▎ ▏  from: https://github.com/hackerb9/ugrep
const BLOCKS: [&str; 8] = ["█", "▉", "▊", "▋", "▌", "▍", "▎", "▏"];
#[cfg(test)]
const TEST_BLOCKS: [&str; 8] = ["0", "1", "2", "3", "4", "5", "6", "7"];

// list shorter than this gets no block at all
const MIN_LENGTH: usize = 2;

fn ease_out_expo(x: f64) -> f64 {
    if x == 1.0 {
        1.0
    } else {
        1.0 - 2f64.powf(-10.0 * x)
    }
}

// second half of the range is mirror of the first half
fn mirror(x: f64) -> f64 {
    let xx = if x > 0.5 { 1.0 - x } else { x };
    ease_out_expo(xx * 2.0)
}

fn index(zero_indexed: usize, length: usize) -> Option<usize> {
    if length < MIN_LENGTH {
        return None;
    }
    let ratio = zero_indexed as f64 / (length - 1) as f64;
    let mut eased = mirror(ratio);
    if eased < 0.0 {
        eased = 0.0;
    }
    if eased >= 1.0 {
        eased = 0.99999;
    }
    Some((BLOCKS.len() as f64 * eased).floor() as usize)
}

pub fn range(text: &str, zero_indexed: usize, length: usize) -> String {
    match index(zero_indexed, length) {
        Some(i) => format!("{} {}", BLOCKS[i], text),
        None => text.to_string(),
    }
}

#[cfg(test)]
fn range_test(text: &str, zero_indexed: usize, length: usize) -> String {
    match index(zero_indexed, length) {
        Some(i) => format!("{} {}", TEST_BLOCKS[i], text),
        None => text.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // cases from lib/range.unit.js
    #[test]
    fn middle_is_thin() {
        assert_eq!(range_test("abc", 4, 9), "7 abc");
    }

    #[test]
    fn ends_are_thick() {
        assert_eq!(range_test("abc", 8, 9), "0 abc");
        assert_eq!(range_test("abc", 0, 9), "0 abc");
    }

    #[test]
    fn single_row_not_processed() {
        assert_eq!(range("abc", 0, 1), "abc");
    }

    #[test]
    fn two_rows() {
        assert_eq!(range("abc", 0, 2), "█ abc");
        assert_eq!(range("abc", 1, 2), "█ abc");
    }
}
