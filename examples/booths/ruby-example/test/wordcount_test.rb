#!/usr/bin/env ruby

require 'minitest/autorun'
require_relative '../src/wordcount'

class WordCounterTest < Minitest::Test
  def test_count_empty_string
    result = WordCounter.count("")
    assert_equal 0, result[:lines]
    assert_equal 0, result[:words]
    assert_equal 0, result[:chars]
  end

  def test_count_single_word
    result = WordCounter.count("hello")
    assert_equal 1, result[:lines]
    assert_equal 1, result[:words]
    assert_equal 5, result[:chars]
  end

  def test_count_multiple_words
    result = WordCounter.count("hello world")
    assert_equal 1, result[:lines]
    assert_equal 2, result[:words]
    assert_equal 11, result[:chars]
  end

  def test_count_multiple_lines
    result = WordCounter.count("hello\nworld\n")
    assert_equal 2, result[:lines]
    assert_equal 2, result[:words]
    assert_equal 12, result[:chars]
  end

  def test_format_result_includes_counts
    counts = { lines: 5, words: 10, chars: 50 }
    result = WordCounter.format_result(counts, "test.txt")
    assert_includes result, "5"
    assert_includes result, "10"
    assert_includes result, "50"
  end
end
