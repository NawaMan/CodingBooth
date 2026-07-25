# Ruby Example

This example is a Ruby 3.3 development environment with Jupyter notebook support. The bundled `wordcount` program counts the lines, words, and characters in a file or piped stdin and prints the totals in colorized output using the `colorize` gem. The draw here is IRuby, the Ruby Jupyter kernel, already installed and registered for you. Wiring up IRuby normally means chasing native gem dependencies like the ZeroMQ bindings before a notebook will even see a Ruby kernel — this booth has done that legwork ahead of time. Open a notebook, select Ruby, and you are running gems and inspecting values cell by cell straight away, turning Ruby into an interactive playground instead of a script-and-rerun loop.

**Stack:** Ruby 3.3, Jupyter Notebook, IRuby kernel

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/ruby-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Ruby kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Ruby 3.3                             |
| Notebook           | Jupyter with IRuby kernel            |
| VS Code extensions | Ruby language support                |
