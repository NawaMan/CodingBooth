# Phase 6: Templates & Validation

## Tasks

31. Create example templates (go, python, java, nodejs, rust, spring, django, claude-code, ssh, etc.)
32. Create `quick-mode.toml`
33. Build template validation tool (for CI/GitHub Actions — check typos, circular deps, missing deps)
34. Add `--verbose` logging throughout the design flow

## Example Templates to Create

### languages/go/spec.toml
```toml
display-name = "Go"
display-order = 30
tags = ["golang", "backend"]

[[setups]]
name = "go--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "latest"
  choices = ["latest", "1.24", "1.23", "1.22"]
```

### languages/python/spec.toml
```toml
display-name = "Python"
display-order = 10
tags = ["python", "scripting"]

[[setups]]
name = "python--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "latest"
  choices = ["latest", "3.12", "3.11", "3.10"]
```

### languages/java/spec.toml
```toml
display-name = "Java"
display-order = 40
tags = ["java", "jvm"]

[[setups]]
name = "jdk--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "JDK Version"
  type = "choice"
  default = "21"
  choices = ["24", "21", "17", "11"]

  [[setups.params]]
  name = "vendor"
  display-name = "Vendor"
  type = "choice"
  default = "temurin"
  choices = ["temurin", "corretto", "zulu", "oracle"]
```

### languages/go/extension/spec.toml
```toml
display-name = "VS Code Extension"
display-order = 10
tags = ["vscode", "ide"]

[[setups]]
name = "go-code-extension--setup.sh"
order = 75
preference = "recommended"
```

### languages/java/maven/spec.toml
```toml
display-name = "Maven"
display-order = 20
tags = ["build", "java"]

[[setups]]
name = "mvn--setup.sh"
order = 65
preference = "recommended"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "3.9.6"
  choices = ["3.9.6", "3.9.5", "3.8.8"]
```

### credentials/ssh/spec.toml
```toml
display-name = "SSH Keys"
display-order = 10
tags = ["git", "authentication"]

[[run-args]]
values = ["-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro"]
preference = "required"
```

### tools/claude-code/spec.toml
```toml
display-name = "Claude Code"
display-order = 10
tags = ["ai", "assistant", "anthropic"]

[[setups]]
name = "claude-code--setup.sh"
order = 70
preference = "required"

[[run-args]]
values = ["-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro"]
preference = "recommended"

[[run-args]]
values = ["-v", "~/.claude:/etc/cb-home-seed/.claude:ro"]
preference = "recommended"
```

### frameworks/spring/spec.toml
```toml
display-name = "Spring Boot"
display-order = 10
tags = ["java", "web", "backend"]

# Auto-selects Java when Spring is selected
requires = ["languages/java"]

[[setups]]
name = "spring-boot--setup.sh"
order = 65
preference = "required"
```

### frameworks/django/spec.toml
```toml
display-name = "Django"
display-order = 20
tags = ["python", "web", "backend"]

# Auto-selects Python when Django is selected
requires = ["languages/python"]

[[setups]]
name = "django--setup.sh"
order = 65
preference = "required"
```

## quick-mode.toml

```toml
# Suggested location: /templates/quick-mode.toml

[python]
templates = ["python", "python-code-extension"]
variant = "codeserver"

[nodejs]
templates = ["nodejs", "nodejs-code-extension"]
variant = "codeserver"

[go]
templates = ["go", "go-code-extension"]
variant = "codeserver"

[java]
templates = ["java", "java-code-extension"]
variant = "codeserver"

[rust]
templates = ["rust", "rust-code-extension"]
variant = "codeserver"

[empty]
templates = []
variant = "base"

[ai-agent]
templates = ["claude-code", "claude-credentials"]
variant = "base"
```

## Template Validation Tool

Build a validation program to run in CI/GitHub Actions before release. It should check:
- All `spec.toml` and `meta.toml` files parse correctly (no typos)
- All `requires` references point to existing templates
- No circular dependencies in `requires` chains
- All referenced setup scripts exist (either built-in or in the template folder)
- All required fields are present in `spec.toml`
- `quick-mode.toml` references only existing templates

## Open Items

- **Rust setup script** — needs to be created (`rust--setup.sh`)
- **AI Agent templates** — which tools to include (Claude Code confirmed, others TBD)
- **Conflict resolution** — if multiple templates specify same run-arg, last wins? dedupe?
- **Template versioning** — should template version match `coding-booth` binary version exactly, or allow compatibility ranges?
