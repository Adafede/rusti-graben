//! Sample binary entrypoint demonstrating quality baseline.

#[expect(
    clippy::print_stdout,
    reason = "printing the sum is this binary's interface"
)]
fn main() {
    let result = sample_lib::add(10, 20);
    println!("10 + 20 = {result}");
}
