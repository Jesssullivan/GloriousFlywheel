# Contributing to Attic-IaC

Thank you for considering contributing to attic-iac! This project provides self-hosted Attic binary cache infrastructure for Kubernetes clusters.

## Ways to Contribute

- **Bug Reports**: Open an issue describing the problem, your environment, and steps to reproduce
- **Feature Requests**: Describe the feature, use case, and why it would be valuable
- **Documentation**: Improve guides, fix typos, add examples
- **Code**: Fix bugs, implement features, improve modules
- **Testing**: Try deployments in different environments and report findings

## Development Setup

### Prerequisites

- Nix with flakes enabled
- OpenTofu or Terraform
- Kubernetes cluster (for testing)
- GitLab account (for testing CI components)

### Local Setup

```bash
# Clone and enter development environment
git clone https://github.com/Jesssullivan/attic-iac.git
cd attic-iac

# Load Nix devShell
direnv allow
# or manually: nix develop

# Configure your organization
cp config/organization.example.yaml config/organization.yaml
# Edit with your test cluster details

# Run checks
just check
```

## Code Style

### OpenTofu/Terraform

- Use 2-space indentation
- Run `tofu fmt` before committing
- Add comments explaining complex logic
- Use descriptive variable names
- Include validation blocks for variables

### Documentation

- Use GitHub-flavored Markdown
- Keep line length under 100 characters (soft limit)
- Include code examples where applicable
- Update table of contents when adding sections

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(module): add support for external S3
fix(runners): correct HPA scaling thresholds
docs(quick-start): clarify GitLab Agent setup
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Scopes: `module`, `stack`, `runners`, `app`, `ci`, `docs`

## Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. **Make your changes**:
   - Write code
   - Add tests if applicable
   - Update documentation
4. **Test your changes**:
   ```bash
   just check                  # Run all validations
   tofu validate              # Validate configs
   ```
5. **Commit with conventional commits**:
   ```bash
   git commit -m "feat(runners): add support for custom runner images"
   ```
6. **Push and create PR**:
   ```bash
   git push origin feat/your-feature-name
   ```
7. **Describe your changes** in the PR:
   - What problem does it solve?
   - How did you test it?
   - Any breaking changes?

## Testing

### Module Testing

```bash
# Validate a specific module
cd tofu/modules/your-module
tofu init -backend=false
tofu validate
```

### Stack Testing

```bash
# Plan a stack deployment (dry-run)
ENV=dev just tofu-plan attic
```

### App Testing

```bash
# Test the runner dashboard
cd app
pnpm install
pnpm check      # Type checking
pnpm test       # Unit tests
pnpm build      # Build verification
```

## Documentation Guidelines

When adding new features:

1. Update relevant docs in `docs/`
2. Add examples to `examples/` if applicable
3. Update `README.md` if it affects quick start
4. Add entry to `docs/customization-guide.md` for new options

## Issue Labels

- `bug` - Something isn't working
- `enhancement` - New feature request
- `documentation` - Documentation improvements
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention needed
- `question` - Questions about usage

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inspiring community for all.

### Our Standards

- **Be respectful** of differing viewpoints
- **Be collaborative** - we're all learning
- **Be patient** - remember everyone was a beginner once
- **Be constructive** in feedback

### Unacceptable Behavior

- Harassment, discrimination, or personal attacks
- Publishing others' private information
- Other conduct inappropriate for a professional setting

### Enforcement

Violations can be reported to the project maintainers. All complaints will be reviewed and investigated.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

- **Documentation**: Check [docs/](docs/)
- **Discussions**: Use [GitHub Discussions](https://github.com/Jesssullivan/attic-iac/discussions)
- **Issues**: Open an [issue](https://github.com/Jesssullivan/attic-iac/issues)

## Maintainers

This project is currently maintained by:

- **Jess Sullivan** ([@Jesssullivan](https://github.com/Jesssullivan))

Originally developed for Tinyland.dev infrastructure.

---

Thank you for contributing!
