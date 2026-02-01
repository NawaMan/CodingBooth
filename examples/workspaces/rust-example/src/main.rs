/// FizzBuzz - A classic programming exercise
///
/// Rules:
/// - If divisible by 3: "Fizz"
/// - If divisible by 5: "Buzz"
/// - If divisible by both: "FizzBuzz"
/// - Otherwise: the number itself

pub fn fizzbuzz(n: u32) -> String {
    match (n % 3, n % 5) {
        (0, 0) => String::from("FizzBuzz"),
        (0, _) => String::from("Fizz"),
        (_, 0) => String::from("Buzz"),
        _ => n.to_string(),
    }
}

pub fn fizzbuzz_range(start: u32, end: u32) -> Vec<String> {
    (start..=end).map(fizzbuzz).collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let (start, end) = match args.len() {
        3 => {
            let start: u32 = args[1].parse().expect("Start must be a number");
            let end: u32 = args[2].parse().expect("End must be a number");
            (start, end)
        }
        _ => {
            eprintln!("🔢 FizzBuzz - The classic programming exercise");
            eprintln!("");
            eprintln!("Rules:");
            eprintln!("  - Divisible by 3: Fizz");
            eprintln!("  - Divisible by 5: Buzz");
            eprintln!("  - Divisible by both: FizzBuzz");
            eprintln!("");
            eprintln!("Usage: fizzbuzz <start> <end>");
            eprintln!("");
            eprintln!("Examples:");
            eprintln!("  fizzbuzz 1 15    Print FizzBuzz from 1 to 15");
            eprintln!("  fizzbuzz 1 100   Print FizzBuzz from 1 to 100");
            std::process::exit(1);
        }
    };

    for result in fizzbuzz_range(start, end) {
        println!("{}", result);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fizz() {
        assert_eq!(fizzbuzz(3), "Fizz");
        assert_eq!(fizzbuzz(6), "Fizz");
        assert_eq!(fizzbuzz(9), "Fizz");
    }

    #[test]
    fn test_buzz() {
        assert_eq!(fizzbuzz(5), "Buzz");
        assert_eq!(fizzbuzz(10), "Buzz");
        assert_eq!(fizzbuzz(20), "Buzz");
    }

    #[test]
    fn test_fizzbuzz() {
        assert_eq!(fizzbuzz(15), "FizzBuzz");
        assert_eq!(fizzbuzz(30), "FizzBuzz");
        assert_eq!(fizzbuzz(45), "FizzBuzz");
    }

    #[test]
    fn test_number() {
        assert_eq!(fizzbuzz(1), "1");
        assert_eq!(fizzbuzz(2), "2");
        assert_eq!(fizzbuzz(7), "7");
    }

    #[test]
    fn test_range() {
        let result = fizzbuzz_range(1, 5);
        assert_eq!(result, vec!["1", "2", "Fizz", "4", "Buzz"]);
    }
}
