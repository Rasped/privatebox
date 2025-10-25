# Documentation style guide

This document defines the writing standards for all PrivateBox documentation, including user guides, technical documentation, and customer communications.

## Headline capitalization

Use sentence case for all headings and subheadings.

**Correct:**
- ## Getting started
- ### Step 1: Connect to your network
- ## What's in the box

**Incorrect:**
- ## Getting Started
- ### Step 1: Connect to Your Network
- ## What's In The Box

**Exception:** Proper nouns remain capitalized (OPNsense, Portainer, Caddy, Caddyfile, PrivateBox, etc.)

## Emphasis and formatting

### Do not emphasize negative words

Do not use bold or caps for words like "not", "don't", "never", or "NOT".

**Correct:**
- What it does not do:
- This is not a commercial VPN service

**Incorrect:**
- What it does NOT do:
- This is **not** a commercial VPN service
- What it does NOT DO:

### Avoid marketing language

Do not use words that add emphasis without information:

**Avoid:**
- Important
- Critical
- Powerful
- Amazing
- Incredible
- Simply
- Just
- Easy/easily (when describing tasks)
- Obviously
- Clearly

**Correct:**
- ## Configure your existing router
- You have 5 minutes after first boot

**Incorrect:**
- ## Critical prerequisite: Configure your existing router
- **Important:** You have 5 minutes after first boot
- This is a critical step
- This powerful feature

### Bold text usage

Use bold sparingly and only for:
- Section labels (Note:, Warning:, Prerequisite:)
- UI elements users need to click ("Click **Add stack**")
- Field names in forms ("**Username:** admin")

Do not use bold for emphasis or to make text "stand out".

### Diagram usage

- Do not embed screenshots or photos in Markdown files.
- Prefer Mermaid diagrams to illustrate hardware layouts, workflows, or sequences.
- Place diagrams immediately after the paragraph that introduces them.
- Keep diagrams brief and readable in plain text (avoid more than about eight nodes).

## Tone and voice

### Be direct and factual

State information without editorial commentary.

**Correct:**
- The system will take 5 minutes to boot
- Backups are stored on the PrivateBox itself

**Incorrect:**
- The system will take just 5 minutes to boot
- Unfortunately, backups are stored on the PrivateBox itself
- Thankfully, the system boots quickly

### Assume user intelligence

Do not explain why something is important unless technically necessary. Users can make their own judgments.

**Correct:**
- Disable DHCP on your existing router

**Incorrect:**
- You must disable DHCP on your existing router (this is critical because...)

### Remove fluff

If a word can be removed without losing meaning, remove it.

**Correct:**
- Download your backup file

**Incorrect:**
- Download your backup file (this is a critical step)

## Terminology

### Consistent product naming

- **PrivateBox** - the product (capitalized)
- **privatebox.lan** - the URL (lowercase)

### Avoid technical jargon in user guides

Use simple language for user-facing documentation. Technical accuracy is important, but clarity is more important.

**User guides:**
- "network segment" instead of "VLAN" (on first reference, then use VLAN)
- "container" instead of "containerized microservice"

**Technical documentation:**
- Use precise technical terms

### Capitalization of UI elements

Match the capitalization shown in the actual UI.

**Example:** If the button says "Deploy stack", write "Click **Deploy stack**" (not "Deploy Stack")

### Preferred component names

- Use "management VM" when referring to the container host.
- Use "Subnet Router VM" for the VPN routing virtual machine.
- Refer to the automation interface as "Semaphore" (capitalized).
- Refer to the service dashboard as "Homer dashboard".

## Structure

### Section numbering

Use numbers for sequential steps:
- ## 1. First step
- ## 2. Second step

Do not number non-sequential sections.

### Step formatting

**Multi-step procedures:**

### Step 1: Do the first thing

1. First action
2. Second action
3. Third action

### Step 2: Do the second thing

**Single-step procedures:**

No numbering needed if there's only one step.

## Email-specific rules

### Warmth is acceptable

Emails can be more personal than documentation:
- "I'm excited to get your PrivateBox to you" - acceptable in email
- "Thank you for your support" - acceptable in email

### Subject lines

Use sentence case:
- **Correct:** Your PrivateBox is on the way
- **Incorrect:** Your PrivateBox Is On The Way

### Signature

Keep signatures personal and simple:
```
Rasmus
Sub Rosa
```

## Punctuation

### Dashes

Do not use em dashes (—). Use hyphens (-) or restructure the sentence.

**Correct:**
- The system will restart - this takes about 2 minutes
- The system will restart (this takes about 2 minutes)
- The system will restart. This takes about 2 minutes.

**Incorrect:**
- The system will restart—this takes about 2 minutes (uses em dash)

## Lists

### Unordered lists

Use hyphens (-) for consistency:
```
- First item
- Second item
- Third item
```

### Ordered lists

Use numbers for sequential steps:
```
1. First step
2. Second step
3. Third step
```

## Examples and code

### Code blocks

Always include language identifier:
```yaml
version: '3.3'
```

### Terminal commands

Use code formatting for all commands:
```bash
nano /var/data/caddy/Caddyfile
```

### URLs

Display as plain text or inline code:
- Plain: https://privatebox.lan
- Code: `https://privatebox.lan`

Do not use markdown links in printed materials (use full URLs).

## Common patterns

### Prerequisites

**Format:**
```
## Prerequisite

You must have already created your Portainer admin account.
```

Not:
- Prerequisites (plural if only one)
- Important Prerequisites
- Critical Prerequisites

### Notes and warnings

**Format:**
```
**Note:** The networks section is essential.
```

Not:
- **Important Note:**
- **Please Note:**

### Questions in FAQ

Use sentence case:
- ### What is PrivateBox?
- ### Can I upgrade the hardware?

Not:
- ### What Is PrivateBox?
- ### Can I Upgrade The Hardware?

## File naming

- Use lowercase with hyphens: getting-started.md
- Not: Getting-Started.md, getting_started.md, GettingStarted.md

## Version

This style guide applies to all documentation created after October 2025.
