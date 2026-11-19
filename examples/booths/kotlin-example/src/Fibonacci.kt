/**
 * Fibonacci - Generate Fibonacci sequence
 *
 * The Fibonacci sequence: 0, 1, 1, 2, 3, 5, 8, 13, 21, ...
 * Each number is the sum of the two preceding ones.
 */

fun fibonacci(n: Int): Long {
    if (n <= 0) return 0
    if (n == 1) return 1

    var a = 0L
    var b = 1L
    for (i in 2..n) {
        val next = a + b
        a = b
        b = next
    }
    return b
}

fun fibonacciSequence(count: Int): List<Long> {
    return (0 until count).map { fibonacci(it) }
}

fun main(args: Array<String>) {
    if (args.isEmpty()) {
        println("Fibonacci Sequence Generator")
        println("")
        println("Generate numbers from the famous Fibonacci sequence,")
        println("where each number is the sum of the two before it.")
        println("")
        println("Usage: fibonacci <count>")
        println("")
        println("Examples:")
        println("  fibonacci 10    Show first 10 Fibonacci numbers")
        println("  fibonacci 20    Show first 20 Fibonacci numbers")
        return
    }

    val count = args[0].toIntOrNull()
    if (count == null || count < 1) {
        println("Error: Please provide a positive integer")
        return
    }

    val sequence = fibonacciSequence(count)
    println("First $count Fibonacci numbers:")
    sequence.forEachIndexed { index, value ->
        println("  F($index) = $value")
    }
}
