# CBT0001 - "booth wrapper not found in this directory tree"

## Summary

You ran `booth` from a directory tree that does not contain a project `booth` wrapper script.

Typical message:

```text
CodingBooth wrapper not found in this directory tree.
What happened: booth was installed as a shell function, but no project booth script exists in the current path or parents.
```

## Why this happens

`booth shell-config` installs a shell function named `booth`.

That function searches upward from your current directory (`$PWD`) for an executable `booth` file.  
If no `booth` file exists in the current path or any parent directory, it cannot dispatch to a project wrapper.

This is common when running from directories like `/tmp`, `/home`, or other non-project folders.

## Quick fixes

1. Run from a CodingBooth project folder (or its subdirectory) that contains `booth`:

```bash
cd /path/to/project
./booth install
```

2. Or run a project wrapper by absolute path from anywhere:

```bash
/path/to/project/booth install
```

3. If the current folder should become a CodingBooth project, install `booth` there:

```bash
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
```

## Verify what `booth` resolves to

```bash
type -a booth
```

- If it shows `booth is a function`, you are using the shell function dispatcher.
- If it shows only a path/script, you are calling a concrete wrapper file.

## Prevention tips

- Keep using `booth` from inside project directories.
- For automation, prefer explicit wrapper paths (`/path/to/project/booth`) to avoid ambiguity.
