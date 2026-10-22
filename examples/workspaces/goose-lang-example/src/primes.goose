// Prints every prime up to a limit, then how many there were.
//
//   goose-lang src/primes.goose -- 20                     run in-process (TinyCC)
//   goose-lang build src/primes.goose -o primes && ./primes 20   native, via gcc

import std;
import os;

// No allocator anywhere: the flags live on a data stack and are freed when the
// function returns, and the result is built straight into the caller's variable.
fn primes_up_to(limit: i64) -> i64[>..] {
    var out: i64[>..] = [];
    if limit < 2 { return out; }
    var flags: u8[>..] = [];
    flags.resize(limit + 1, 1);
    var i = 2;
    while i * i <= limit {
        if flags[i] == 1 {
            var j = i * i;
            while j <= limit { flags[j] = 0; j += i; }
        }
        i++;
    }
    for n, k in flags {
        if k >= 2 && n == 1 { out.push(k); }
    }
    return out;
}

fn main() {
    var limit = 100;
    let argv = args();
    if argv.len >= 2 {
        let n, ok = parse_int(argv[1]);
        if !ok {
            write_stderr(str("not a number: ", argv[1], "\n"));
            return;
        }
        limit = n;
    }
    let primes = primes_up_to(limit);
    for p in primes { print(p); }
    print("Found ", primes.len, " primes up to ", limit);
}
