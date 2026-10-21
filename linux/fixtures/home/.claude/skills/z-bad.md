---
name:
description: malformed on purpose (name has no value)
---

# z-bad

Deliberately malformed fixture: frontmatter `name:` carries no value, so
FrontmatterParser yields an empty name and the scanner must tolerate this
file as unparsed (no crash, no skill row).
