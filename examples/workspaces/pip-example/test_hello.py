# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

"""pytest for hello.py, driven through click's own test runner."""

from click.testing import CliRunner

from hello import PACKAGES, main, package_table


def test_greets_by_name() -> None:
    result = CliRunner().invoke(main, ["--name", "booth"])
    assert result.exit_code == 0
    assert "Installed by" in result.output


def test_table_lists_every_package() -> None:
    assert package_table().row_count == len(PACKAGES)


def test_unknown_option_is_an_error() -> None:
    result = CliRunner().invoke(main, ["--nope"])
    assert result.exit_code != 0
