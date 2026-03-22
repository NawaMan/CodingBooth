package main

// Param represents a configurable parameter for a template or extension.
type Param struct {
	Name     string
	Default  string
	Suggests []string
}

// Extension represents a child item under a Template.
type Extension struct {
	Name        string
	Description string
	Detail      string
	AutoSelect  bool
	Requires    []string
	Params      []Param
}

// Template represents a top-level selectable item with optional extensions.
type Template struct {
	Name        string
	Description string
	Detail      string
	Category    string
	Extensions  []Extension
	Requires    []string
	Params      []Param
}

func GenerateSampleData() []Template {
	return []Template{
		// === Languages ===
		{
			Name: "go", Description: "Go programming language", Category: "Languages",
			Detail: "Installs Go toolchain, sets up GOPATH, and configures common Go tools like gopls and delve.",
			Params: []Param{{Name: "GO_VERSION", Default: "1.24.1", Suggests: []string{"1.24.1", "1.23.5", "1.22.10"}}},
			Extensions: []Extension{
				{Name: "linter", Description: "golangci-lint", Detail: "Installs golangci-lint for comprehensive Go linting.", AutoSelect: true},
				{Name: "air", Description: "Hot reload for Go", Detail: "Installs Air for live-reloading Go applications during development."},
				{Name: "protobuf", Description: "Protocol Buffers for Go", Detail: "Installs protoc-gen-go for gRPC and Protocol Buffer support.", Requires: []string{"protobuf"}},
			},
		},
		{
			Name: "python", Description: "Python programming language", Category: "Languages",
			Detail: "Installs Python via pyenv with pip and virtualenv support.",
			Params: []Param{{Name: "PYTHON_VERSION", Default: "3.12", Suggests: []string{"3.12", "3.11", "3.10"}}},
			Extensions: []Extension{
				{Name: "poetry", Description: "Python dependency management", Detail: "Installs Poetry for managing Python project dependencies and packaging."},
				{Name: "jupyter", Description: "Jupyter notebook support", Detail: "Installs JupyterLab for interactive Python notebooks."},
				{Name: "ruff", Description: "Fast Python linter", Detail: "Installs Ruff, an extremely fast Python linter written in Rust.", AutoSelect: true},
			},
		},
		{
			Name: "nodejs", Description: "Node.js runtime", Category: "Languages",
			Detail: "Installs Node.js via nvm with npm and yarn support.",
			Params: []Param{{Name: "NODE_VERSION", Default: "22", Suggests: []string{"22", "20", "18"}}},
			Extensions: []Extension{
				{Name: "pnpm", Description: "Fast package manager", Detail: "Installs pnpm as an alternative to npm with better disk efficiency."},
				{Name: "typescript", Description: "TypeScript compiler", Detail: "Installs TypeScript globally for type-safe JavaScript development.", AutoSelect: true},
				{Name: "bun", Description: "Bun runtime", Detail: "Installs Bun as a fast JavaScript runtime and toolkit."},
			},
		},
		{
			Name: "rust", Description: "Rust programming language", Category: "Languages",
			Detail: "Installs Rust via rustup with cargo and common components.",
			Extensions: []Extension{
				{Name: "clippy", Description: "Rust linter", Detail: "Enables clippy for catching common Rust mistakes.", AutoSelect: true},
				{Name: "wasm", Description: "WebAssembly target", Detail: "Adds wasm32 target for compiling Rust to WebAssembly."},
			},
		},
		{
			Name: "java", Description: "Java Development Kit", Category: "Languages",
			Detail: "Installs JDK via SDKMAN with Maven and Gradle support.",
			Params: []Param{{Name: "JAVA_VERSION", Default: "21", Suggests: []string{"21", "17", "11"}}},
			Extensions: []Extension{
				{Name: "maven", Description: "Apache Maven", Detail: "Installs Maven for Java project build and dependency management.", AutoSelect: true},
				{Name: "gradle", Description: "Gradle build tool", Detail: "Installs Gradle as an alternative build system for Java projects."},
				{Name: "spring", Description: "Spring Boot CLI", Detail: "Installs Spring Boot CLI for rapid Spring application development."},
				{Name: "quarkus", Description: "Quarkus CLI", Detail: "Installs Quarkus CLI for cloud-native Java development."},
			},
		},
		{
			Name: "dotnet", Description: ".NET SDK", Category: "Languages",
			Detail: "Installs .NET SDK for C#, F#, and VB.NET development.",
			Params: []Param{{Name: "DOTNET_VERSION", Default: "8.0", Suggests: []string{"8.0", "7.0", "6.0"}}},
			Extensions: []Extension{
				{Name: "aspnet", Description: "ASP.NET Core", Detail: "Includes ASP.NET Core runtime for web applications.", AutoSelect: true},
				{Name: "ef", Description: "Entity Framework", Detail: "Installs EF Core tools for database migrations."},
			},
		},
		{
			Name: "ruby", Description: "Ruby programming language", Category: "Languages",
			Detail: "Installs Ruby via rbenv with Bundler.",
			Params: []Param{{Name: "RUBY_VERSION", Default: "3.3", Suggests: []string{"3.3", "3.2", "3.1"}}},
			Extensions: []Extension{
				{Name: "rails", Description: "Ruby on Rails", Detail: "Installs Rails framework for web application development."},
				{Name: "rubocop", Description: "Ruby linter", Detail: "Installs RuboCop for Ruby code style checking.", AutoSelect: true},
			},
		},
		{
			Name: "php", Description: "PHP programming language", Category: "Languages",
			Detail: "Installs PHP with common extensions and Composer.",
			Params: []Param{{Name: "PHP_VERSION", Default: "8.3", Suggests: []string{"8.3", "8.2", "8.1"}}},
			Extensions: []Extension{
				{Name: "composer", Description: "PHP dependency manager", Detail: "Installs Composer for PHP package management.", AutoSelect: true},
				{Name: "laravel", Description: "Laravel framework", Detail: "Installs Laravel installer for rapid PHP web development."},
			},
		},
		{
			Name: "swift", Description: "Swift programming language", Category: "Languages",
			Detail: "Installs Swift toolchain for server-side or CLI development.",
			Extensions: []Extension{
				{Name: "vapor", Description: "Vapor web framework", Detail: "Installs Vapor for server-side Swift web applications."},
			},
		},
		{
			Name: "kotlin", Description: "Kotlin programming language", Category: "Languages",
			Detail: "Installs Kotlin compiler and tooling. Requires JDK.",
			Requires: []string{"java"},
			Extensions: []Extension{
				{Name: "ktor", Description: "Ktor web framework", Detail: "Installs Ktor for building async Kotlin web services."},
			},
		},
		{
			Name: "elixir", Description: "Elixir programming language", Category: "Languages",
			Detail: "Installs Elixir and Erlang/OTP via asdf.",
			Extensions: []Extension{
				{Name: "phoenix", Description: "Phoenix framework", Detail: "Installs Phoenix for real-time Elixir web applications."},
			},
		},
		{
			Name: "zig", Description: "Zig programming language", Category: "Languages",
			Detail: "Installs Zig compiler for low-level systems programming.",
		},
		{
			Name: "haskell", Description: "Haskell programming language", Category: "Languages",
			Detail: "Installs GHC and Cabal via GHCup.",
			Extensions: []Extension{
				{Name: "stack", Description: "Haskell Stack", Detail: "Installs Stack as an alternative Haskell build tool."},
			},
		},

		// === Databases ===
		{
			Name: "postgresql", Description: "PostgreSQL database", Category: "Databases",
			Detail: "Installs PostgreSQL server and client tools.",
			Params: []Param{{Name: "PG_VERSION", Default: "16", Suggests: []string{"16", "15", "14"}}},
			Extensions: []Extension{
				{Name: "pgadmin", Description: "pgAdmin web UI", Detail: "Installs pgAdmin for visual database management."},
				{Name: "postgis", Description: "Geospatial extensions", Detail: "Adds PostGIS for geographic object support."},
			},
		},
		{
			Name: "mysql", Description: "MySQL database", Category: "Databases",
			Detail: "Installs MySQL server and client.",
			Params: []Param{{Name: "MYSQL_VERSION", Default: "8.0", Suggests: []string{"8.0", "5.7"}}},
			Extensions: []Extension{
				{Name: "phpmyadmin", Description: "phpMyAdmin web UI", Detail: "Installs phpMyAdmin for visual MySQL management.", Requires: []string{"php"}},
			},
		},
		{
			Name: "redis", Description: "Redis in-memory store", Category: "Databases",
			Detail: "Installs Redis server for caching and message brokering.",
			Extensions: []Extension{
				{Name: "redisinsight", Description: "Redis GUI", Detail: "Installs RedisInsight for visual Redis management."},
			},
		},
		{
			Name: "mongodb", Description: "MongoDB NoSQL database", Category: "Databases",
			Detail: "Installs MongoDB server and mongosh shell.",
			Extensions: []Extension{
				{Name: "compass", Description: "MongoDB Compass", Detail: "Installs MongoDB Compass GUI for data exploration."},
			},
		},
		{
			Name: "sqlite", Description: "SQLite embedded database", Category: "Databases",
			Detail: "Installs SQLite3 command-line tool and development libraries.",
		},
		{
			Name: "cassandra", Description: "Apache Cassandra", Category: "Databases",
			Detail: "Installs Cassandra for distributed NoSQL database needs.",
			Requires: []string{"java"},
		},
		{
			Name: "elasticsearch", Description: "Elasticsearch search engine", Category: "Databases",
			Detail: "Installs Elasticsearch for full-text search and analytics.",
			Requires: []string{"java"},
			Extensions: []Extension{
				{Name: "kibana", Description: "Kibana dashboard", Detail: "Installs Kibana for Elasticsearch data visualization.", AutoSelect: true},
			},
		},
		{
			Name: "neo4j", Description: "Neo4j graph database", Category: "Databases",
			Detail: "Installs Neo4j for graph-based data modeling.",
			Requires: []string{"java"},
		},

		// === Tools ===
		{
			Name: "git", Description: "Git version control", Category: "Tools",
			Detail: "Configures Git with useful aliases, delta diff viewer, and global gitignore.",
			Extensions: []Extension{
				{Name: "gh", Description: "GitHub CLI", Detail: "Installs the GitHub CLI for managing repos, PRs, and issues from the terminal.", AutoSelect: true},
				{Name: "git-lfs", Description: "Git Large File Storage", Detail: "Installs Git LFS for tracking large files in Git repositories."},
				{Name: "lazygit", Description: "Terminal UI for Git", Detail: "Installs lazygit for an interactive terminal Git experience."},
			},
		},
		{
			Name: "docker", Description: "Docker containers", Category: "Tools",
			Detail: "Installs Docker Engine and Docker Compose for container management.",
			Extensions: []Extension{
				{Name: "compose", Description: "Docker Compose", Detail: "Ensures docker-compose plugin is available for multi-container apps.", AutoSelect: true},
				{Name: "buildx", Description: "Docker Buildx", Detail: "Installs Buildx for advanced multi-platform image builds."},
				{Name: "portainer", Description: "Portainer container UI", Detail: "Installs Portainer for visual container management."},
			},
		},
		{
			Name: "kubernetes", Description: "Kubernetes tools", Category: "Tools",
			Detail: "Installs kubectl and common Kubernetes utilities.",
			Requires: []string{"docker"},
			Extensions: []Extension{
				{Name: "helm", Description: "Helm package manager", Detail: "Installs Helm for managing Kubernetes application packages.", AutoSelect: true},
				{Name: "k9s", Description: "K9s terminal UI", Detail: "Installs K9s for interactive Kubernetes cluster management."},
				{Name: "minikube", Description: "Local Kubernetes", Detail: "Installs Minikube for running a local Kubernetes cluster."},
			},
		},
		{
			Name: "terraform", Description: "Infrastructure as Code", Category: "Tools",
			Detail: "Installs Terraform for declarative infrastructure management.",
			Extensions: []Extension{
				{Name: "tflint", Description: "Terraform linter", Detail: "Installs TFLint for catching Terraform configuration issues.", AutoSelect: true},
				{Name: "terragrunt", Description: "Terraform wrapper", Detail: "Installs Terragrunt for managing multiple Terraform modules."},
			},
		},
		{
			Name: "protobuf", Description: "Protocol Buffers compiler", Category: "Tools",
			Detail: "Installs the protoc compiler for Protocol Buffer serialization.",
		},
		{
			Name: "make", Description: "GNU Make", Category: "Tools",
			Detail: "Ensures GNU Make is available for build automation.",
		},
		{
			Name: "tmux", Description: "Terminal multiplexer", Category: "Tools",
			Detail: "Installs tmux for managing multiple terminal sessions.",
			Extensions: []Extension{
				{Name: "tpm", Description: "Tmux Plugin Manager", Detail: "Installs TPM for easy tmux plugin management.", AutoSelect: true},
			},
		},
		{
			Name: "zsh", Description: "Z Shell", Category: "Tools",
			Detail: "Installs and configures Zsh as the default shell.",
			Extensions: []Extension{
				{Name: "ohmyzsh", Description: "Oh My Zsh", Detail: "Installs Oh My Zsh framework for Zsh configuration.", AutoSelect: true},
				{Name: "starship", Description: "Starship prompt", Detail: "Installs Starship for a fast, customizable shell prompt."},
				{Name: "fzf", Description: "Fuzzy finder", Detail: "Installs fzf for fuzzy file and history searching."},
			},
		},
		{
			Name: "nginx", Description: "Nginx web server", Category: "Tools",
			Detail: "Installs Nginx for serving web content and reverse proxying.",
		},
		{
			Name: "caddy", Description: "Caddy web server", Category: "Tools",
			Detail: "Installs Caddy with automatic HTTPS.",
		},
		{
			Name: "awscli", Description: "AWS CLI", Category: "Tools",
			Detail: "Installs the AWS Command Line Interface for cloud management.",
			Extensions: []Extension{
				{Name: "sam", Description: "AWS SAM CLI", Detail: "Installs AWS SAM for serverless application development."},
				{Name: "cdk", Description: "AWS CDK", Detail: "Installs AWS CDK for infrastructure as code with familiar languages.", Requires: []string{"nodejs"}},
			},
		},
		{
			Name: "gcloud", Description: "Google Cloud CLI", Category: "Tools",
			Detail: "Installs the Google Cloud SDK for GCP management.",
		},
		{
			Name: "azure-cli", Description: "Azure CLI", Category: "Tools",
			Detail: "Installs the Azure CLI for Microsoft cloud management.",
		},
		{
			Name: "playwright", Description: "Playwright testing", Category: "Tools",
			Detail: "Installs Playwright for end-to-end browser testing.",
			Requires: []string{"nodejs"},
			Extensions: []Extension{
				{Name: "browsers", Description: "Install test browsers", Detail: "Downloads Chromium, Firefox, and WebKit for Playwright tests.", AutoSelect: true},
			},
		},
		{
			Name: "jq", Description: "JSON processor", Category: "Tools",
			Detail: "Installs jq for command-line JSON processing and filtering.",
		},
		{
			Name: "yq", Description: "YAML processor", Category: "Tools",
			Detail: "Installs yq for command-line YAML processing.",
		},
		{
			Name: "ripgrep", Description: "Fast search tool", Category: "Tools",
			Detail: "Installs ripgrep (rg) for extremely fast recursive text search.",
		},
		{
			Name: "bat", Description: "Better cat", Category: "Tools",
			Detail: "Installs bat, a cat clone with syntax highlighting and Git integration.",
		},
		{
			Name: "fd", Description: "Better find", Category: "Tools",
			Detail: "Installs fd, a fast and user-friendly alternative to find.",
		},
		{
			Name: "exa", Description: "Modern ls replacement", Category: "Tools",
			Detail: "Installs exa for a modern, colorful directory listing.",
		},
		{
			Name: "htop", Description: "Interactive process viewer", Category: "Tools",
			Detail: "Installs htop for interactive system process monitoring.",
		},

		// === AI Tools ===
		{
			Name: "claude-code", Description: "Claude Code CLI", Category: "AI Tools",
			Detail: "Installs Claude Code, Anthropic's AI coding assistant CLI.",
			Requires: []string{"nodejs"},
			Extensions: []Extension{
				{Name: "mcp-servers", Description: "MCP server support", Detail: "Configures Model Context Protocol servers for enhanced AI capabilities.", AutoSelect: true},
			},
		},
		{
			Name: "copilot", Description: "GitHub Copilot", Category: "AI Tools",
			Detail: "Enables GitHub Copilot for AI-powered code suggestions in supported editors.",
			Extensions: []Extension{
				{Name: "copilot-chat", Description: "Copilot Chat", Detail: "Enables Copilot Chat for conversational AI assistance.", AutoSelect: true},
			},
		},
		{
			Name: "cursor", Description: "Cursor AI editor", Category: "AI Tools",
			Detail: "Installs Cursor, an AI-first code editor based on VS Code.",
		},
		{
			Name: "aider", Description: "Aider AI pair programmer", Category: "AI Tools",
			Detail: "Installs Aider for AI-assisted pair programming in the terminal.",
			Requires: []string{"python"},
		},
		{
			Name: "ollama", Description: "Local LLM runner", Category: "AI Tools",
			Detail: "Installs Ollama for running large language models locally.",
			Extensions: []Extension{
				{Name: "open-webui", Description: "Open WebUI", Detail: "Installs Open WebUI for a ChatGPT-like interface to local models.", Requires: []string{"docker"}},
			},
		},
		{
			Name: "continue", Description: "Continue AI extension", Category: "AI Tools",
			Detail: "Installs the Continue VS Code extension for open-source AI code assistance.",
		},

		// === IDEs ===
		{
			Name: "vscode", Description: "Visual Studio Code", Category: "IDEs",
			Detail: "Installs VS Code with commonly used settings and keybindings.",
			Extensions: []Extension{
				{Name: "prettier", Description: "Prettier formatter", Detail: "Installs Prettier extension for automatic code formatting.", AutoSelect: true},
				{Name: "eslint", Description: "ESLint extension", Detail: "Installs ESLint extension for JavaScript/TypeScript linting."},
				{Name: "gitlens", Description: "GitLens extension", Detail: "Installs GitLens for advanced Git visualization in VS Code."},
				{Name: "remote-ssh", Description: "Remote SSH", Detail: "Installs Remote SSH extension for editing files on remote machines."},
				{Name: "docker-ext", Description: "Docker extension", Detail: "Installs Docker extension for container management.", Requires: []string{"docker"}},
			},
		},
		{
			Name: "neovim", Description: "Neovim editor", Category: "IDEs",
			Detail: "Installs Neovim with a modern configuration framework.",
			Extensions: []Extension{
				{Name: "lazyvim", Description: "LazyVim config", Detail: "Installs LazyVim for a batteries-included Neovim setup.", AutoSelect: true},
				{Name: "telescope", Description: "Telescope fuzzy finder", Detail: "Installs Telescope.nvim for fuzzy finding files and content."},
				{Name: "treesitter", Description: "Tree-sitter parsing", Detail: "Installs nvim-treesitter for advanced syntax highlighting."},
			},
		},
		{
			Name: "intellij", Description: "IntelliJ IDEA", Category: "IDEs",
			Detail: "Installs IntelliJ IDEA Community Edition for JVM development.",
			Requires: []string{"java"},
		},
		{
			Name: "goland", Description: "GoLand IDE", Category: "IDEs",
			Detail: "Installs JetBrains GoLand for Go development.",
			Requires: []string{"go"},
		},
		{
			Name: "zed", Description: "Zed editor", Category: "IDEs",
			Detail: "Installs Zed, a high-performance collaborative code editor.",
		},

		// === Browsers ===
		{
			Name: "chrome", Description: "Google Chrome", Category: "Browsers",
			Detail: "Installs Google Chrome browser.",
			Extensions: []Extension{
				{Name: "devtools", Description: "Chrome DevTools extras", Detail: "Configures additional Chrome DevTools features.", AutoSelect: true},
			},
		},
		{
			Name: "firefox", Description: "Mozilla Firefox", Category: "Browsers",
			Detail: "Installs Firefox browser.",
			Extensions: []Extension{
				{Name: "devtools", Description: "Firefox DevTools extras", Detail: "Configures additional Firefox developer tools.", AutoSelect: true},
			},
		},
		{
			Name: "chromium", Description: "Chromium browser", Category: "Browsers",
			Detail: "Installs the open-source Chromium browser.",
		},

		// === Desktops ===
		{
			Name: "xfce", Description: "XFCE desktop", Category: "Desktops",
			Detail: "Installs XFCE4 lightweight desktop environment.",
			Extensions: []Extension{
				{Name: "thunar", Description: "Thunar file manager", Detail: "Installs Thunar for XFCE file management.", AutoSelect: true},
				{Name: "panel-plugins", Description: "Panel plugins", Detail: "Installs common XFCE panel plugins for system monitoring."},
			},
		},
		{
			Name: "kde", Description: "KDE Plasma desktop", Category: "Desktops",
			Detail: "Installs KDE Plasma desktop environment with Wayland support.",
			Extensions: []Extension{
				{Name: "dolphin", Description: "Dolphin file manager", Detail: "Installs Dolphin for KDE file management.", AutoSelect: true},
				{Name: "konsole", Description: "Konsole terminal", Detail: "Installs Konsole terminal emulator.", AutoSelect: true},
			},
		},
		{
			Name: "i3", Description: "i3 tiling WM", Category: "Desktops",
			Detail: "Installs i3 tiling window manager for keyboard-driven workflows.",
			Extensions: []Extension{
				{Name: "i3status", Description: "i3 status bar", Detail: "Installs i3status for a customizable status bar.", AutoSelect: true},
				{Name: "rofi", Description: "Rofi launcher", Detail: "Installs Rofi application launcher."},
				{Name: "picom", Description: "Picom compositor", Detail: "Installs Picom for transparency and compositing effects."},
			},
		},
		{
			Name: "sway", Description: "Sway Wayland WM", Category: "Desktops",
			Detail: "Installs Sway, an i3-compatible Wayland compositor.",
			Extensions: []Extension{
				{Name: "waybar", Description: "Waybar status bar", Detail: "Installs Waybar for a customizable Wayland status bar.", AutoSelect: true},
				{Name: "wofi", Description: "Wofi launcher", Detail: "Installs Wofi application launcher for Wayland."},
			},
		},
	}
}
