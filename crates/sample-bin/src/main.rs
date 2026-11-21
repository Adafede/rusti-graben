//! Sample binary entrypoint demonstrating quality baseline.

#[expect(
    clippy::print_stdout,
    reason = "printing the sum is this binary's interface"
)]
fn main() {
    println!("10 + 20 = {}", sample_lib::add(10, 20));
}
