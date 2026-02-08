# Contributing to attic-iac

This is the **upstream public repository** for GloriousFlywheel -- a self-deploying
infrastructure system where GitLab runners deploy themselves, a Nix binary cache caches
its own derivations, and a monitoring dashboard watches the runners that deploy it.

Organizations deploy this by creating private **overlay repositories** that layer
site-specific configuration on top of this upstream module via Bzlmod.

## Ways to Contribute

- **Bug reports**: Open an issue with your environment details and steps to reproduce
- **Feature requests**: Describe the use case and why it would be valuable
- **OpenTofu modules**: Improve existing modules or add new ones in `tofu/modules/`
- **Runner dashboard**: SvelteKit 5 app in `app/` (TypeScript, Skeleton, Tailwind CSS 4)
- **Documentation**: Improve guides in `docs/`, fix diagrams, add examples
- **Docs site**: SvelteKit + mdsvex static site in `docs-site/`
- **Testing**: Deploy in different cluster environments and report findings

## Development Setup

### Prerequisites

- Nix with flakes enabled (provides all other tooling via devShell)
- A Kubernetes cluster for testing deployments
- GitLab account for testing CI components

### Local Setup

```bash
git clone https://github.com/Jesssullivan/attic-iac.git
cd attic-iac
direnv allow   # or: nix develop

cp config/organization.example.yaml config/organization.yaml
# Edit with your test cluster details

just check     # Run all validations
```

### Workspace Packages

This is a pnpm workspace with two packages:

| Package | Path | Purpose |
|---------|------|---------|
| `runner-dashboard` | `app/` | SvelteKit 5 monitoring UI (adapter-node) |
| `glorious-flywheel-docs` | `docs-site/` | Documentation site (adapter-static) |

```bash
just dev          # Start dashboard dev server
just docs-dev     # Start docs site dev server
just app-test     # Run dashboard tests
```

## Code Style

### OpenTofu

- 2-space indentation, run `tofu fmt` before committing
- Descriptive variable names with validation blocks
- Comments for complex logic only

### TypeScript / Svelte

- Follow existing patterns in `app/src/`
- Use `$derived()` and `$state()` runes (Svelte 5)
- Type server load data explicitly

### Documentation

- GitHub-flavored Markdown with Mermaid diagrams (no ASCII art)
- Relative links that work in both GitHub and the docs site
- No emoji

### Commit Messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
feat(runners): add support for custom runner images
fix(module): correct HPA scaling thresholds
docs(quick-start): clarify overlay deployment steps
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Scopes: `module`, `stack`, `runners`, `app`, `docs`, `ci`, `build`, `overlay`

## Pull Request Process

1. Fork the repository
2. Create a branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. Make changes, add tests if applicable, update docs
4. Verify:
   ```bash
   just check        # All validations
   just app-test     # Dashboard tests (78 tests, 9 files)
   ```
5. Commit with conventional commits
6. Push and open a PR describing what problem it solves and how you tested it

## Testing

### OpenTofu Modules

```bash
cd tofu/modules/your-module
tofu init -backend=false
tofu validate
```

### Stack Planning

```bash
just tofu-plan attic
```

### Dashboard App

```bash
cd app
pnpm check      # Type checking
pnpm test       # Unit tests (vitest)
pnpm build      # Build verification
```

### Docs Site

```bash
cd docs-site
pnpm build      # Static site generation (adapter-static)
```

## Overlay Development

If you are working on an overlay repository (not this upstream repo):

1. Clone both repos as siblings:
   ```bash
   git clone https://github.com/Jesssullivan/attic-iac.git ~/git/attic-iac
   git clone <your-overlay> ~/git/your-overlay
   ```

2. Edits to `~/git/attic-iac/` are picked up automatically via `local_path_override`

3. Run builds from the overlay directory -- Bazel resolves upstream automatically

See [docs/architecture/overlay-system.md](docs/architecture/overlay-system.md) for details.

## Documentation Guidelines

When adding features:

1. Update relevant docs in `docs/`
2. Use Mermaid for diagrams
3. Update `docs/infrastructure/customization-guide.md` for new configuration options
4. Update `README.md` if it affects the quick start

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

- [Documentation](https://jesssullivan.github.io/attic-iac/)
- [GitHub Discussions](https://github.com/Jesssullivan/attic-iac/discussions)
- [Issues](https://github.com/Jesssullivan/attic-iac/issues)

## Maintainers

- **Jess Sullivan** ([@Jesssullivan](https://github.com/Jesssullivan))
