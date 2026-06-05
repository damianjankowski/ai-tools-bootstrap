# conventional-commit skill

Creates a git commit with a conventional commit message by analyzing staged changes.

## Quick start

1. Stage your changes: `git add <files>`
2. Ask Claude: "create a commit" or "commit my changes"
3. Skill analyzes the diff and creates the commit
4. Push with: `git push`

## How it works

The skill:
1. Checks for staged changes
2. Analyzes the diff to infer type (feat, fix, docs, etc.)
3. Detects scope from file paths
4. Suggests a message like: `feat(auth): validate jwt tokens`
5. Creates the commit
6. Done — you can push when ready

## Message types

- **feat:** new feature or functionality
- **fix:** bug fix
- **docs:** documentation changes only
- **refactor:** code restructuring without functional change
- **test:** test files only
- **chore:** dependencies, config, tooling
- **ci:** CI/CD related changes

## Examples

```bash
# Add feature in auth module
git add src/auth/tokens.py
# → Suggested: feat(auth): validate jwt tokens

# Fix bug in database module
git add src/db/query.py
# → Suggested: fix(db): handle null values properly

# Update README
git add README.md
# → Suggested: docs: update readme

# Update dependencies
git add package.json
# → Suggested: chore: update dependencies
```

## Message format

The skill generates messages in the format:

```
<type>(<scope>): <subject>
```

- Type and subject are required
- Scope is inferred from file paths (optional but preferred)
- Subject is imperative, lowercase, no period

## Amending commits

If the suggested message isn't quite right, you can amend it:

```bash
git commit --amend -m "feat(auth): your corrected message"
```

## Implementation

- `SKILL.md` — skill definition and workflow
- `scripts/suggest_commit.py` — analyzes diff and generates message suggestions
