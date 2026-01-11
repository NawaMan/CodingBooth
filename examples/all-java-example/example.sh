#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


../../workspace --variant base -- '
jbang --quiet - <<EOF one "two 2"
import java.nio.file.*;
import java.util.Arrays;

class Test {
    public static void main(String[] args) {
        System.out.println("🚀 JDK: " + System.getProperty("java.version"));
        System.out.println("📁 CWD: " + Paths.get("").toAbsolutePath());
        System.out.println("🔧 Args: " + Arrays.toString(args));
        for (int i = 0; i < 3; i++) {
            System.out.println("line " + i);
        }
    }
}
EOF
' \
# 2>/dev/null      # Uncomment to get only the output of the program
