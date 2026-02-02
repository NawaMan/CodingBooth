# Changelog

## [0.14.0]

### Added
- Non-root package installation support -- previously only root was allowed to install packages.
    - Homebrew setup script (`homebrew--setup.sh`) for non-root package installation inside containers
    - Pip install helper script (`pip--install.sh`) for installing Python packages during image build
    - NPM install helper script (`npm--install.sh`) for installing Node.js packages during image build
    - Cargo install helper script (`cargo--install.sh`) for installing Rust packages during image build
    - Bun install helper script (`bun--install.sh`) for installing Bun packages during image build
    - RubyGems install helper script (`gem--install.sh`) for installing Ruby packages during image build
    - Deno install helper script (`deno--install.sh`) for installing Deno packages during image build

