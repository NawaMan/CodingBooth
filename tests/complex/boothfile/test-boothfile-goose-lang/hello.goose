// Fixture for test--boothfile-goose-lang.sh: exercises the stdlib, a growable
// array and a function with two results.
import std;

fn divmod(a: i64, b: i64) -> i64, i64 { return a / b, a % b; }

fn main() {
    var squares: i64[>..] = [];
    for i in 5 { squares.push(i * i); }
    let q, r = divmod(17, 5);
    print("hello from goose: ", squares, " ", q, " ", r);
}
