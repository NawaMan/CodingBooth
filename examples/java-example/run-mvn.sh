#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This is to be run from with in the container.

mvn -q clean install exec:java 2>&1 \
  | grep -v 'sun.misc.Unsafe' \
  | grep -v 'com.google.inject.internal.aop.HiddenClassDefiner'
