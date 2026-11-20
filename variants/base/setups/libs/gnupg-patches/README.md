# GnuPG upstream fixes

Commits from GnuPG's own repository (https://github.com/gpg/gnupg) that a release lacks, as
`https://github.com/gpg/gnupg/commit/<commit>.patch?full_index=1` serves them, byte for byte.
`gnupg--setup.sh` applies them when it builds that release from source, after checking each
against the SHA-256 it pins. They are kept here because GitHub answers 503 for a commit's
`.patch` far more often than not, which failed image builds.

| File | Release | What it fixes |
|---|---|---|
| `42386bcf8861f04c1bdec5cbb139a03da83d8ef9.patch` | 2.5.24 | [T8469](https://dev.gnupg.org/T8469): import of unprotected ECDH keys |
| `5523cec6913bcbd1a374d183899a6f298d2c0e32.patch` | 2.5.24 | T8469, second part |

These files are part of GnuPG and carry its licence, GPL-3.0-or-later, not this repository's.
The same two are in CodingBoothPrebuilt's `tools/gnupg/patches/`; keep them in step.
