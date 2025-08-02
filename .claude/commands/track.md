---
description: Update work log and changelog
---

Track command fired.

1. Review WORK-LOG.md and CHANGELOG.md
2. Check current git status and recent commits
3. Add to WORK-LOG.md:
   - Active investigations/debugging
   - Current bugs and issues
   - Tasks in progress
   - Features being developed
   - Pending fixes
4. Move to CHANGELOG.md:
   - Completed fixes with dates
   - Implemented features
   - Resolved bugs
   - Configuration changes
5. Commit with descriptive message about the actual work:
   - Example: "Fix Caddy backends and implement password management"
   - NOT: "Update work log and changelog"
6. Push to repository

Format entries:
- WORK-LOG: `- [Category] Brief description (current status/blockers)`
- CHANGELOG: `- 2025-08-02: [Category] What was accomplished`

Categories: [Bug], [Task], [Feature], [Fix], [Config], [Docs], [Investigation]