from std.sys import argv


def factorial(n: Int) -> Int:
    if n <= 1:
        return 1
    return n * factorial(n - 1)


def main() raises:
    var args = argv()
    var n = 5
    if len(args) >= 2:
        n = Int(String(args[1]))
    if n < 0:
        print("Error: factorial is not defined for negative numbers")
        return
    print(String(n) + "! = " + String(factorial(n)))
