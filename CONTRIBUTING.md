# Contributing to PrivateBox

Thank you for your interest in contributing to PrivateBox! This document provides guidelines for contributing to the project.

## Git workflow best practices

### Commit messages

Follow the conventional commits format:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Example: `feat: Add OPNsense VM provisioning support`

### Before committing

1. **Test locally** - Ensure your changes work
2. **Review changes** - Use `git diff` to review what you're committing
3. **Stage intentionally** - Use `git add -p` for partial staging
4. **Keep commits focused** - One logical change per commit

### Working with branches

1. Create feature branches for new work:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Keep branches up to date:
   ```bash
   git fetch origin
   git rebase origin/main
   ```

3. Squash commits before merging:
   ```bash
   git rebase -i origin/main
   ```

### Pull requests

1. Create clear PR titles and descriptions
2. Reference any related issues
3. Ensure all tests pass
4. Keep PRs focused and reasonably sized

## Development setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Rasped/privatebox.git
   cd privatebox
   ```

2. Test bootstrap scripts in a Proxmox environment
3. Use the included health check scripts to verify functionality

## Testing

- Test all bootstrap scripts on a clean Proxmox installation
- Verify network auto-discovery works in your environment
- Check that Portainer and Semaphore install correctly

## Code style

- Use clear, descriptive variable names
- Add comments for complex logic
- Follow existing patterns in the codebase
- Keep functions focused and modular

## Questions?

Feel free to open an issue for any questions about contributing.