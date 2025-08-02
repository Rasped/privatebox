---
description: Update work log and changelog
---

Track command fired.

1. Review WORK-LOG.md and CHANGELOG.md
2. Check current git status and recent commits
3. Update WORK-LOG.md:
   - Add new items to Uncategorized section
   - Move items between priority sections as needed
   - Update status of existing items
   - Priority sections: Critical (P1), Important (P2), Nice to Have (P3)
4. Move completed items to CHANGELOG.md:
   - Add date and clear description
   - Remove from WORK-LOG.md
5. Commit with descriptive message about the actual work:
   - Example: "Fix Caddy backends and implement password management"
   - NOT: "Update work log and changelog"
6. Push to repository

Priorities:
- Critical (P1): v1 blockers, must have
- Important (P2): Should have, significant issues
- Nice to Have (P3): Can wait, minor improvements

Format entries:
- WORK-LOG: `- [Category] Brief description (current status/blockers)`
- CHANGELOG: `- 2025-08-02: [Category] What was accomplished`

Categories: [Bug], [Task], [Feature], [Fix], [Config], [Docs], [Investigation]