# Lazarus Example

This example is a small Lazarus desktop app, Prime Finder. It is a real Lazarus project: a
`.lpi` project file, a form designed in a `.lfm` file, and a plain Pascal unit that does the
work. Pick a limit, press **Find primes**, and the form lists every prime up to it. Lazarus is
the classic route to a native GUI in Object Pascal, and it is awkward to install: a compiler,
the LCL, its widgetset and headers, and the FPC sources the IDE wants. This booth sets all of it
up in an XFCE desktop. You get the IDE in the browser, and `lazbuild` builds the same project
from a terminal.

**Stack:** Free Pascal 3.2 · Lazarus 4.4 (LCL, GTK2) · XFCE desktop

## Quick start

```bash
# 1. Launch the booth — opens the XFCE desktop in your browser
cd examples/workspaces/lazarus-example
booth

# 2. From the host (or a terminal on the desktop)
just --list
just check 30            # build, load the form, press "Find primes", print the result
just run                 # show the Prime Finder window on the desktop
just ide                 # open the project in the Lazarus IDE
```

Or double-click **Lazarus** on the desktop and open `primefinder.lpi`.

## What's included

| Component       | Details                                                        |
|-----------------|----------------------------------------------------------------|
| Compiler        | Free Pascal (`fpc`)                                            |
| IDE             | Lazarus, with a desktop and dock icon                          |
| Build           | `lazbuild primefinder.lpi`, which needs no display (CI-friendly) |
| VS Code support | Pascal language extension                                      |
| Sample          | `primefinder.lpr`, `mainunit.pas` + `mainunit.lfm`, `primes.pas` |

Selected as `fpc+lazarus` with the `xfce` variant. On a variant without a desktop, the same
selection installs `lazbuild` and the LCL but not the IDE, so headless builds still work. Pin the
Lazarus series with the `LAZARUS_VERSION` build arg in `.booth/Boothfile`.

## Testing

```bash
./run-automatic-on-host-test.sh
```

The test starts the desktop booth and builds the app with `lazbuild`. It then runs the app with
`--self-test 30`, which loads the real form and clicks its button. Last, it checks that the IDE
is installed, has its desktop icon, and starts.
