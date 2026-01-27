#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


../../coding-booth --variant base -- '
python3 - <<PY
import os, sys
print("CWD in container:", os.getcwd())
print("Args:", sys.argv)
for i in range(3):
    print("line", i)
PY
' \
# 2>/dev/null      # Uncomment to get only the output of the program
