#![doc = include_str!("../README.md")]

/// Adds two standard integers together cleanly.
///
/// # Examples
///
/// ```
/// use sample_lib::add;
/// assert_eq!(add(2, 3), 5, "two plus three");
/// ```
#[must_use]
pub const fn add(left: usize, right: usize) -> usize {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let result = add(2, 2);
        assert_eq!(result, 4, "two plus two");
    }
}
