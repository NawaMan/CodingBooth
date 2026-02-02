const std = @import("std");
const print = std.debug.print;

/// Prime Number Generator
/// Finds and displays prime numbers up to a given limit.

pub fn isPrime(n: u64) bool {
    if (n < 2) return false;
    if (n == 2) return true;
    if (n % 2 == 0) return false;

    var i: u64 = 3;
    while (i * i <= n) : (i += 2) {
        if (n % i == 0) return false;
    }
    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    const limit_str = args.next();
    if (limit_str == null) {
        print("Prime Number Generator\n\n", .{});
        print("Find all prime numbers up to a given limit.\n", .{});
        print("A prime number is only divisible by 1 and itself.\n\n", .{});
        print("Usage: primes <limit>\n\n", .{});
        print("Examples:\n", .{});
        print("  primes 50     Find primes up to 50\n", .{});
        print("  primes 100    Find primes up to 100\n", .{});
        return;
    }

    const limit = std.fmt.parseInt(u64, limit_str.?, 10) catch {
        print("Error: Please provide a valid positive integer\n", .{});
        return;
    };

    print("Prime numbers up to {d}:\n", .{limit});
    var count: usize = 0;
    var n: u64 = 2;
    while (n <= limit) : (n += 1) {
        if (isPrime(n)) {
            if (count > 0) print(", ", .{});
            if (count > 0 and count % 10 == 0) print("\n", .{});
            print("{d}", .{n});
            count += 1;
        }
    }
    print("\n\nTotal: {d} primes found\n", .{count});
}
