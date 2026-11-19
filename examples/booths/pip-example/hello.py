# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

"""A tiny CLI built from the booth's pip-installed packages.

click parses the arguments, pyfiglet draws the banner, and rich prints a table
of the packages this booth installs. No network: httpx is only listed.
"""

from importlib.metadata import version

import click
from pyfiglet import figlet_format
from rich.console import Console
from rich.table import Table

PACKAGES = {
    "click": "this command's options",
    "rich": "the table below",
    "pyfiglet": "the banner above",
    "pytest": "just test",
    "ruff": "just lint",
    "black": "just lint",
    "cowsay": "just run",
    "httpx": "HTTP client (installed, not used here)",
}


def package_table() -> Table:
    table = Table(title="Installed by `install pip` in .booth/Boothfile")
    table.add_column("Package")
    table.add_column("Version")
    table.add_column("Used for")
    for name, use in PACKAGES.items():
        table.add_row(name, version(name), use)
    return table


@click.command()
@click.option("--name", default="world", help="Who to greet.")
def main(name: str) -> None:
    """Greet NAME with a banner and list the booth's Python packages."""
    console = Console()
    console.print(figlet_format(f"hi {name}", font="small"), highlight=False)
    console.print(package_table())


if __name__ == "__main__":
    main()
