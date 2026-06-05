---
name: conventional-commit
description: Use when you want to create a git commit with a conventional commit message. The skill examines your staged changes, suggests an appropriate commit message following https://www.conventionalcommits.org/en/v1.0.0/, and creates the commit. Output is always in English. Triggers on phrases like "create a commit", "commit my changes", "make a commit", or "commit these changes".
---

# conventional-commit

Creates a properly formatted conventional commit by analyzing staged changes and suggesting an appropriate message.

## Workflow

1. Check if files are staged — if not, tell user to run `git add` and return
2. Run `git diff --cached` to analyze staged changes
3. Suggest a conventional commit message based on:
   - Type: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`
   - Scope: inferred from changed file paths
   - Subject: imperative, lowercase, no period, under 50 chars
4. Create commit with the suggested message
5. Output success: "Committed. Push with: `git push`"

## Message format

```
<type>(<scope>): <subject>
```

Example: `feat(auth): add jwt token validation`

## Implementation steps

1. **Check staged files:**
   ```bash
   git diff --cached --name-only
   ```
   If output is empty, stop and prompt user to stage files.

2. **Analyze the diff:**
   - Get full diff: `git diff --cached`
   - Run `scripts/suggest_commit.py` to analyze changes and suggest message
   - The script examines:
     - File paths to infer scope
     - Change patterns to infer type
     - Summary of what changed to draft subject

3. **Show suggestion to user:**
   ```
   Suggested commit message:
   
   feat(auth): validate jwt tokens in middleware
   
   Creating commit...
   ```

4. **Create the commit:**
   ```bash
   git commit -m "<suggested-message>"
   ```

5. **Confirm success:**
   ```
   ✓ Committed
   
   Push with: git push
   ```

## Error cases

- **No staged files:** "No staged changes. Run `git add <files>` first, then try again."
- **Not in a git repo:** "Not in a git repository."
- **Commit fails:** Show git error message.

## Message type detection logic

- **feat:** new files added, or significant logic changes in src/
- **fix:** bug fixes, error handling, conditional logic fixes
- **docs:** changes in *.md, docs/, README files only
- **refactor:** restructuring without functional change, moving files
- **test:** test files only (test/, tests/, *_test.py, *.test.js, etc.)
- **chore:** dependencies, config, tooling changes (package.json, pyproject.toml, Makefile, etc.)
- **ci:** CI/CD files (.github/, .gitlab-ci.yml, Dockerfile, etc.)

## Scope detection logic

Scope is optional but preferred. Infer from:
- Module/package name from file paths (src/auth/ → `auth`)
- Component name (frontend/components/Button → `button`)
- First meaningful directory after src/ or project root
- If multiple scopes, pick the most significant one
