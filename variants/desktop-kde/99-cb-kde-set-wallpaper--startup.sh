#!/bin/bash

if command -v /usr/bin/plasma-apply-wallpaperimage >/dev/null 2>&1; then
  /usr/bin/plasma-apply-wallpaperimage /usr/share/backgrounds/codingbooth-wallpaper.png 2>/dev/null || true
fi