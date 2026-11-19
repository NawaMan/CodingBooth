#!/usr/bin/env ruby
# Word Counter - counts words, lines, and characters

require 'colorize'

module WordCounter
  def self.count(text)
    {
      lines: text.lines.count,
      words: text.split(/\s+/).reject(&:empty?).count,
      chars: text.length
    }
  end

  def self.format_result(counts, filename = nil)
    header = filename ? "📄 #{filename}".blue : "📄 stdin".blue
    lines = "  Lines: #{counts[:lines]}".green
    words = "  Words: #{counts[:words]}".yellow
    chars = "  Chars: #{counts[:chars]}".cyan

    [header, lines, words, chars].join("\n")
  end
end

if __FILE__ == $0
  if ARGV.empty? && !$stdin.tty?
    # Read from stdin
    text = $stdin.read
    counts = WordCounter.count(text)
    puts WordCounter.format_result(counts)
  elsif ARGV.length > 0
    # Read from file
    filename = ARGV[0]
    unless File.exist?(filename)
      puts "Error: File not found: #{filename}".red
      exit 1
    end
    text = File.read(filename)
    counts = WordCounter.count(text)
    puts WordCounter.format_result(counts, filename)
  else
    puts "📄 Word Counter - Count lines, words, and characters in text"
    puts ""
    puts "Usage: wordcount.rb [file]"
    puts "       cat file | wordcount.rb"
    puts ""
    puts "Examples:"
    puts "  wordcount.rb README.md      Count from file"
    puts "  echo 'hello' | wordcount.rb Count from stdin"
    exit 1
  end
end
