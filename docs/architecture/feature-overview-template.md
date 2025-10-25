---
status: planned  # planned | implemented | deprecated
implemented_in: null  # version number when implemented (e.g., v1.2.0)
category: core  # core | security | networking | services | management
complexity: medium  # low | medium | high
dependencies: []  # list of other features/components
maintenance_priority: normal  # low | normal | high | critical
target_version: null  # planned version (e.g., v1.5.0)
last_updated: YYYY-MM-DD
---

# Feature Name

## Overview

Brief description of what this feature does and why it exists.

**Key capabilities:**
- Capability 1
- Capability 2
- Capability 3

## Business context

Why does PrivateBox need this feature?
- Customer value proposition
- Competitive differentiation
- Regulatory/compliance needs

## Architecture

### Components

Describe the main components:
- **Component 1:** Purpose and responsibility
- **Component 2:** Purpose and responsibility

### Data flow

How does data/requests flow through this feature?

```
User → Component A → Component B → Result
```

### Integration points

What does this feature integrate with?
- External services
- Other PrivateBox features
- Hardware dependencies

## Technical details

### Configuration

Key configuration files and parameters:
- `/path/to/config.yml` - Purpose
- Environment variables needed

### Deployment

How is this feature deployed?
- Ansible playbook: `ansible/playbooks/services/feature-name.yml`
- Container/service name
- Network requirements

### Monitoring

How do we know it's working?
- Health check endpoints
- Log locations
- Key metrics

## Security considerations

- Authentication/authorization model
- Data encryption (at rest, in transit)
- Attack surface
- Threat mitigations

## User impact

### End users
What do customers see/experience?

### Advanced users
What advanced configuration options exist?

## Operational notes

### Troubleshooting
Common issues and solutions

### Maintenance
Regular maintenance tasks

### Backup/Recovery
What needs to be backed up? How to restore?

## Future enhancements

(Optional) Known limitations or planned improvements

## Related documentation

- ADRs: [ADR-NNNN](./adr-nnnn-title.md)
- User guides: [Guide Name](/docs/guides/path/to/guide.md)
- External docs: Links to relevant external documentation
