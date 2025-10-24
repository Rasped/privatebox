# PrivateBox Documentation

Welcome to the PrivateBox documentation! This documentation is organized for different audiences.

## For Users

### Getting Started
New to PrivateBox? Start here:
- [Getting Started Guides](./guides/getting-started/) - Setup and basic usage

### Advanced Usage
Want to customize your PrivateBox?
- [Advanced Guides](./guides/advanced/) - VLANs, VPN, custom services, and more

## For Developers

### Architecture
Understanding how PrivateBox works:
- [Architecture Documentation](./architecture/) - System design, ADRs, and technical details
- [Architecture Index](./architecture/README.md) - Feature overview and status

### Contributing
Want to contribute to PrivateBox?
- [Contributing Guide](./contributing/) - Development setup, testing, and workflow

## Documentation Structure

```
/docs/
├── guides/              # User-facing documentation
│   ├── getting-started/ # Setup and basic usage
│   └── advanced/        # Advanced configuration
├── architecture/        # Technical architecture and ADRs
│   ├── recovery-system/
│   ├── network-architecture/
│   ├── deployment-automation/
│   └── [feature-name]/
└── contributing/        # Developer documentation
```

## Documentation as Code

This documentation follows documentation-as-code principles:
- Version-controlled alongside code
- Uses YAML frontmatter for metadata
- Organized by feature and audience
- Architecture Decision Records (ADRs) preserve decision history
- Can be read directly on GitHub or served as local help site

## Finding What You Need

**"How do I...?"** → Check [Getting Started](./guides/getting-started/) or [Advanced Guides](./guides/advanced/)

**"How does X work?"** → Check [Architecture Documentation](./architecture/)

**"Why did we choose Y?"** → Check the ADRs in the relevant architecture folder

**"I want to contribute"** → Check [Contributing Guide](./contributing/)

## Need Help?

- [Troubleshooting Guide](./guides/getting-started/common-issues.md) *(to be created)*
- [GitHub Issues](https://github.com/Rasped/privatebox/issues)
- [Community Forum](https://community.privatebox.io) *(future)*
