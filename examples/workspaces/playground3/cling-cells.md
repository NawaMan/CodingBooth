# Notebook cells for the xeus-cling kernel

These snippets only make sense inside a Jupyter notebook running the **C++17
(xcpp17)** kernel — they exercise cling's REPL features (auto-print, on-the-fly
includes) that don't exist in a normal `.cpp` file.

Open `http://localhost:18888` (the port set in `.booth/Boothfile`), create a
new notebook with the **C++17** kernel, and paste each block as its own cell.

> ⚠️ The xeus-cling kernel is experimental and unmaintained upstream. If a cell
> hangs or crashes, restart the kernel from the notebook UI.

---

**Cell 1 — std::cout works the same as a regular program**

```cpp
#include <iostream>
#include <vector>
#include <string>

std::vector<std::string> v = {"hello", "from", "xeus-cling"};
for (auto& s : v) std::cout << s << " ";
std::cout << std::endl;
```

---

**Cell 2 — last expression auto-prints (this is the killer cling feature)**

```cpp
int x = 21;
x * 2
```

Should print `42` without an explicit `std::cout`.

---

**Cell 3 — pull in headers and run algorithms on the fly**

```cpp
#pragma cling add_include_path("/usr/include")
#include <numeric>

std::vector<int> xs{1, 2, 3, 4, 5};
std::accumulate(xs.begin(), xs.end(), 0)
```

Should print `15`.
