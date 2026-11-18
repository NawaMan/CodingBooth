#!/usr/bin/env php
<?php
/**
 * Anagram Checker - Check if two words/phrases are anagrams
 *
 * Two words are anagrams if they contain the same letters in different order.
 * Examples: "listen" and "silent", "evil" and "vile"
 */

class AnagramChecker
{
    /**
     * Normalize a string by removing non-letters and lowercasing
     */
    public static function normalize(string $text): string
    {
        return strtolower(preg_replace('/[^a-zA-Z]/', '', $text));
    }

    /**
     * Get sorted characters of a string
     */
    public static function sortedChars(string $text): string
    {
        $chars = str_split(self::normalize($text));
        sort($chars);
        return implode('', $chars);
    }

    /**
     * Check if two strings are anagrams
     */
    public static function areAnagrams(string $text1, string $text2): bool
    {
        return self::sortedChars($text1) === self::sortedChars($text2);
    }

    /**
     * Format the result message
     */
    public static function formatResult(string $text1, string $text2): string
    {
        $isAnagram = self::areAnagrams($text1, $text2);
        $status = $isAnagram ? "ARE" : "are NOT";
        return "\"$text1\" and \"$text2\" $status anagrams";
    }
}

function showHelp(): void
{
    echo "Anagram Checker\n";
    echo "\n";
    echo "Check if two words or phrases are anagrams of each other.\n";
    echo "Anagrams contain the same letters in a different order.\n";
    echo "\n";
    echo "Usage: anagram.php <word1> <word2>\n";
    echo "\n";
    echo "Examples:\n";
    echo "  anagram.php listen silent     (are anagrams)\n";
    echo "  anagram.php evil vile         (are anagrams)\n";
    echo "  anagram.php hello world       (not anagrams)\n";
}

// Main
$args = array_slice($argv, 1);

if (count($args) < 2) {
    showHelp();
    exit(0);
}

echo AnagramChecker::formatResult($args[0], $args[1]) . "\n";
