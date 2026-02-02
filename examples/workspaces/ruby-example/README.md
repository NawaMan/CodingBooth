# Word Counter

A simple word counting CLI built with Ruby.

## Features
- Count words, lines, and characters in text
- Read from file or stdin
- Colorful output using the colorize gem

## Usage

```bash
ruby src/wordcount.rb file.txt
echo "hello world" | ruby src/wordcount.rb
```

## Development

Run directly:
```bash
ruby src/wordcount.rb [file]
```

Run tests:
```bash
ruby test/wordcount_test.rb
```
