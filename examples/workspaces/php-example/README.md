# PHP Example

This example is a minimal PHP environment with Composer for dependency management. The bundled anagram checker takes two words or phrases, normalizes and sorts their letters, and reports whether they are anagrams of each other. The selling point here is that your host stays untouched: PHP and Composer come up in a single line and run entirely inside the container. Anyone who has installed PHP locally knows the mess — a system PHP some other tool depends on, clashing versions, php.ini and extension juggling you are afraid to disturb. This booth sidesteps all of it, giving you a clean, disposable PHP and Composer environment for the demo (or your own project) while your machine's system PHP is never added, changed, or endangered.

**Stack:** PHP, Composer

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/php-example
booth

# 2. Inside the booth — run the anagram demo
./run-anagram.sh listen silent
```

## What's included

| Component | Details                              |
|-----------|--------------------------------------|
| Runtime   | PHP CLI                              |
| Package   | Composer                             |
| Sample    | `src/anagram.php`                    |
