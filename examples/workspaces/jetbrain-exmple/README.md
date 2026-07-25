# JetBrains Example

This example bundles a full lineup of JetBrains IDEs into a single CodingBooth desktop environment. It installs nine JetBrains IDEs — IntelliJ IDEA, PyCharm, GoLand, WebStorm, PhpStorm, CLion, Rider, RubyMine, and DataGrip — on a JDK 24 KDE desktop reached over noVNC, with matching demo files to open in each. Multiple things bundled: a whole set of JetBrains IDEs plus a JDK arrive together in one desktop booth. Instead of downloading, licensing, and separately installing nine different IDEs — each gigabytes in size — you open one booth in your browser and every JetBrains tool is already there. It turns "which IDE handles this language?" into a non-question: the full lineup, plus a working JDK and desktop, is a single launch away.

**Stack:** JDK 24, IntelliJ IDEA, PyCharm, GoLand, WebStorm, PhpStorm, CLion, Rider, RubyMine, DataGrip

## Quick start

```bash
# 1. Launch the booth (requires a desktop variant)
cd examples/jetbrain-exmple
../../codingbooth

# 2. Connect to the desktop via your browser
#    Open http://localhost:16901 (noVNC)

# 3. Inside the desktop — launch any IDE from the application menu or terminal
idea         # IntelliJ IDEA
pycharm      # PyCharm
goland       # GoLand
webstorm     # WebStorm
```

## Included IDEs

| IDE        | Language / Purpose       |
|------------|--------------------------|
| IntelliJ   | Java, Kotlin             |
| PyCharm    | Python                   |
| GoLand     | Go                       |
| WebStorm   | JavaScript, TypeScript   |
| PhpStorm   | PHP                      |
| CLion      | C, C++                   |
| Rider      | .NET                     |
| RubyMine   | Ruby                     |
| DataGrip   | Database                 |

## Try the demo files

The workspace includes demo files you can open in the matching IDE:

| File                | Open with  |
|---------------------|------------|
| `Demo.java`        | IntelliJ   |
| `Demo.py`          | PyCharm    |
| `Demo.sh`          | any        |
| `Demo-Java.ipynb`  | IntelliJ   |
| `Demo-Python.ipynb` | PyCharm    |
| `Demo-Bash.ipynb`  | any        |
