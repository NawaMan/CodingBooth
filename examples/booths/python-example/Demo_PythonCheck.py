#!/usr/bin/env python3
"""
Check Python environment, installed packages, and Jupyter kernels.
"""

import os
import sys
import subprocess
from importlib.metadata import version as pkg_version, PackageNotFoundError

def check_environment():
    print("=== Environment Info ===")
    print("Python executable:", sys.executable)
    print("VIRTUAL_ENV:", os.environ.get("VIRTUAL_ENV"))
    print("sys.prefix:", sys.prefix)
    print()

def check_packages():
    print("=== Package Versions ===")
    packages = ["pip", "setuptools", "wheel", "jupyter", "ipykernel", "bash_kernel"]
    for name in packages:
        try:
            ver = pkg_version(name)
            print(f"{name:12s}: {ver}")
        except PackageNotFoundError:
            print(f"{name:12s}: NOT INSTALLED")
    print()

def check_pip_list():
    print("=== pip list (short) ===")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "list", "--disable-pip-version-check"],
            capture_output=True, text=True, check=True
        )
        print("\n".join(result.stdout.splitlines()[:20]))
    except Exception as e:
        print("Error running pip list:", e)
    print()

def check_jupyter_kernels():
    print("=== Jupyter Kernels ===")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "jupyter", "kernelspec", "list"],
            capture_output=True, text=True, check=True
        )
        print(result.stdout)
    except FileNotFoundError:
        print("Jupyter not found.")
    except subprocess.CalledProcessError as e:
        print("Error checking kernels:", e)
        if e.stdout:
            print(e.stdout)
        if e.stderr:
            print(e.stderr)
    print()

if __name__ == "__main__":
    check_environment()
    check_packages()
    check_pip_list()
    check_jupyter_kernels()
