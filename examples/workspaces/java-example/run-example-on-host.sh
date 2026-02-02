#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


../../../codingbooth --variant base --port 22000 -- '
jbang --quiet - <<EOF one "two 2"
import java.nio.file.*;
import java.util.Arrays;

class Test {
    public static void main(String[] args) {
        System.out.println("🚀 JDK: " + System.getProperty("java.version"));
        System.out.println("📁 CWD: " + Paths.get("").toAbsolutePath());
        System.out.println("🔧 Args: " + Arrays.toString(args));
        for (int i = 0; i < args.length; i++) {
            System.out.println("line " + i + ": " + args[i]);
        }
    }
}
EOF
'
