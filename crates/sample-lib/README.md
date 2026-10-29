# sample-lib

Sample library demonstrating the rusti-graben gates. This README is the crate's
documentation (`#![doc = include_str!("../README.md")]`), so the example below
is compiled and run as a doctest.

```rust
use sample_lib::add;

let total = [1, 2, 3].into_iter().fold(0, add);
assert_eq!(total, 6, "sum of a list");
```
