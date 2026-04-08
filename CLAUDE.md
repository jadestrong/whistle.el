# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

whistle.el is an Emacs interface for managing [Whistle](https://github.com/avwo/whistle) proxy rules and values. Whistle is a cross-platform debugging proxy tool similar to Fiddler/Charles. This package provides a comprehensive Emacs-based editor with syntax highlighting, auto-completion, and full CRUD operations for both rules and values.

**Key Concepts:**
- **Rules**: Whistle proxy rules that define how to intercept and modify HTTP/HTTPS traffic (e.g., redirect requests, mock responses, modify headers)
- **Values**: Named content blocks (JSON, HTML, headers, etc.) that can be referenced in rules using `{value-name}` syntax
- **Whistle Server**: HTTP API server running at `http://127.0.0.1:8899` (default) that manages rules and values

## Architecture

The codebase has evolved through multiple versions and currently contains three main implementations:

### 1. **whistle.el** (V2 - Legacy)
Original tabulated-list based interface with separate buffers for rules and values management.

**Key features:**
- `*Whistle Rules*` buffer: List view of all rules with activation status
- `*Whistle Values*` buffer: List view of all values with type detection
- Separate edit buffers for rule/value content
- Direct HTTP API calls to Whistle server endpoints

**Architecture pattern:**
- `whistle-rules-list-mode`: Derived from `tabulated-list-mode` for rules listing
- `whistle-values-list-mode`: Derived from `tabulated-list-mode` for values listing
- `whistle-rule-edit-mode`: Derived from `prog-mode` for rule editing
- `whistle-value-edit-mode`: Derived from `text-mode` for value editing

### 2. **whistle-core.el** (V3 - Current)
Unified file-based editing with local file storage and server synchronization.

**Key innovation:** Single unified file format combining rules and values:
```whistle
# Rules section (regular Whistle syntax)
example.com host://127.0.0.1

# Values section (fenced code blocks)
```user-data
{"name": "test"}
```
```

**Architecture:**
- **File System**: Local `.whistle` files in `~/.whistle/rules/`
- **Metadata System**: JSON metadata tracking in `~/.whistle/metadata.json` for sync state
- **Server Naming**: Uses group-based organization with `\remacs` prefix for rules
- **Hash-based Sync**: MD5 hash comparison for conflict detection
- **Value Transformation**: Automatically transforms `{value-name}` → `{emacs-rule-name}` when syncing to server

**Core functions:**
- `whistle--parse-buffer`: Parses unified format into rules + values alist
- `whistle--format-buffer`: Formats rules + values into unified format
- `whistle-sync-to-server`: One-way sync buffer → server with value reference transformation
- `whistle-load-from-server`: Load rule and associated values from server
- `whistle-save`: Save to local file + optionally sync to server

### 3. **whistle-ts-mode.el** (V3 + Tree-sitter)
Tree-sitter powered major mode with dual-language support.

**Technical approach:**
- Uses `tree-sitter-whistle` grammar for Whistle rules syntax
- Uses built-in `json` grammar for value blocks
- **Range-based parsing**: `treesit-parser-set-included-ranges` separates Whistle regions from JSON regions
- Automatic range updates via `after-change-functions` hook

**Implementation details:**
- `whistle-ts-mode--json-ranges`: Returns list of `(start . end)` cons cells for all ```` ```name ... ``` ```` blocks
- `whistle-ts-mode--whistle-ranges`: Returns ranges for everything outside JSON blocks
- `whistle-ts-mode--language-at-point`: Determines which language parser to use at point
- Electric backtick: Typing ```` ``` ```` at line start expands to value block template

## Whistle HTTP API Reference

All API endpoints are relative to `whistle-base-url` (default: `http://127.0.0.1:8899`).

**Rules API:**
- `GET /cgi-bin/rules/list` → `{list: [{name, data, selected}, ...]}`
- `POST /cgi-bin/rules/add` (params: `name`, `value`, optional `groupName`)
- `POST /cgi-bin/rules/update` (params: `name`, `rules`)
- `POST /cgi-bin/rules/remove` (params: `name`)
- `POST /cgi-bin/rules/rename` (params: `name`, `newName`)
- `POST /cgi-bin/rules/select` (params: `name`) - activate rule
- `POST /cgi-bin/rules/unselect` (params: `name`) - deactivate rule

**Values API:**
- `GET /cgi-bin/values/list` → `{list: [{name, data}, ...]}`
- `POST /cgi-bin/values/add` (params: `name`, `value`, optional `groupName`)
- `POST /cgi-bin/values/update` (params: `name`, `value`)
- `POST /cgi-bin/values/remove` (params: `name`)
- `POST /cgi-bin/values/rename` (params: `name`, `newName`)

**HTTP Implementation:**
- `whistle--http-get`: Wrapper around `url-retrieve` with JSON parsing
- `whistle--http-post`: POST with `application/x-www-form-urlencoded` encoding
- Error callbacks supported for all HTTP functions

## Key Customization Variables

```elisp
;; V3 (whistle-core.el)
whistle-base-url              ; Server URL (default: "http://127.0.0.1:8899")
whistle-rules-directory       ; Local storage (default: "~/.whistle/rules/")
whistle-auto-sync             ; Auto-sync to server on save (default: t)
whistle-rule-prefix           ; Server group prefix (default: "emacs")
whistle-metadata-file         ; Metadata storage (default: "~/.whistle/metadata.json")
whistle-conflict-strategy     ; 'prompt, 'server-wins, or 'local-wins

;; V2 (whistle.el)
whistle-instances             ; List of multiple whistle servers
whistle-auto-refresh          ; Auto-refresh list after operations
whistle-confirm-delete        ; Confirm before deleting
```

## Common Development Tasks

### Testing HTTP API Integration

```elisp
;; Test rule listing
(whistle--http-get "/cgi-bin/rules/list"
                   (lambda (data) (message "Rules: %S" data))
                   (lambda (err) (message "Error: %s" err)))

;; Test rule creation with group
(whistle--http-post "/cgi-bin/rules/add"
                    '(("name" . "test-rule")
                      ("value" . "example.com host://127.0.0.1")
                      ("groupName" . "\remacs"))
                    (lambda (data) (message "Created: %S" data)))
```

### Working with Tree-sitter

The tree-sitter mode requires `tree-sitter-whistle` grammar to be installed:

```bash
# Grammar location (user should have this installed)
# ~/.emacs.d/.local/cache/tree-sitter/whistle.so
```

**Debugging tree-sitter ranges:**
```elisp
;; Check current ranges
(mapcar (lambda (p)
          (list (treesit-parser-language p)
                (treesit-parser-included-ranges p)))
        (treesit-parser-list))

;; Force range update
(whistle-ts-mode--update-ranges)
```

### Adding New Whistle Protocols

The protocol list `whistle-protocols` in both `whistle.el` and `whistle-core.el` defines available protocols for syntax highlighting and completion. To add new protocols:

1. Add to `whistle-protocols` constant (line 341 in whistle.el, line 606 in whistle-core.el)
2. Protocols are used in:
   - Font-lock keywords via `(regexp-opt whistle-protocols 'symbols)`
   - Completion via `whistle-completion-at-point`

### Sync Workflow (V3)

**File → Server sync process:**
1. Parse buffer into rules + values with `whistle--parse-buffer`
2. Transform value references: `{name}` → `{emacs-rule-name}`
3. Ensure group `\remacs` exists
4. Create/update rule with `groupName` parameter
5. Create/update each value with `groupName` parameter
6. Delete orphaned values (on server but not in local file)
7. Update metadata with file/server hashes

**Server → File sync:**
- Currently one-way: only loads from server, doesn't merge changes
- User must manually resolve conflicts if detected

## File Structure Patterns

**V3 Unified Format:**
- Rules section: Standard Whistle syntax (comments start with `#`)
- Values section: Markdown-style fenced code blocks with ```` ```name ... ``` ````
- Value names: `[a-zA-Z0-9._-]+` (alphanumeric, dots, underscores, hyphens)
- Empty line separates rules from values (convention only)

**Local File Naming:**
- Format: `{rule-name}.whistle`
- Directory: `~/.whistle/rules/`
- Metadata: `~/.whistle/metadata.json` (JSON format)

**Server Naming (V3):**
- Rules: `{name}` in group `\remacs`
- Values: `emacs-{rule-name}-{value-name}` in group `\remacs`
- Group prefix `\r` indicates special group in Whistle

## Important Implementation Notes

1. **Buffer-local variables**: `whistle--current-rule-name`, `whistle--file-path`, `whistle--parsed-values` are buffer-local - capture them before async callbacks

2. **Async HTTP callbacks**: The `url-retrieve` callbacks run in temporary buffers - must use closures or switch back to original buffer

3. **Tree-sitter range updates**: Must be called after buffer modifications to maintain correct syntax highlighting in multi-language buffers

4. **Value reference transformation**: Critical for V3 sync - local `{name}` must become `{emacs-rule-name}` on server to avoid conflicts

5. **Whistle group API**: The `groupName` parameter in `/add` endpoints is used for organizational purposes but may not be consistently supported across Whistle versions

6. **Evil mode integration**: Both V2 and V3 include `with-eval-after-load 'evil` blocks for Vim-style keybindings

7. **Auto-mode-alist**: `whistle-ts-mode` is automatically activated for `.whistle` files (line 334 in whistle-ts-mode.el)

## Testing Workflow

Since this is an Emacs package for external API integration:

1. **Start Whistle server**: `w2 start` or `whistle start`
2. **Verify API access**: `curl http://127.0.0.1:8899/cgi-bin/rules/list`
3. **Load package in Emacs**: `M-x load-file RET whistle-core.el RET`
4. **Test commands**:
   - `M-x whistle` → Opens rules list
   - `M-x whistle-edit-rule RET Default RET` → Opens rule editor
   - Edit content, `C-c C-c` to save
   - `C-c C-s` to sync to server
   - `C-c C-a` to activate rule

## Entry Points

**V2 (whistle.el):**
- `M-x whistle` → Menu selection (Rules/Values/Web UI)
- `M-x whistle-rules` → Open rules list
- `M-x whistle-values` → Open values list

**V3 (whistle-core.el + whistle-ts-mode.el):**
- `M-x whistle` → Open rules list view
- `M-x whistle-edit-rule` → Edit specific rule (unified format)

**Key bindings in edit mode:**
- `C-c C-c` - Save (file + optional server sync)
- `C-c C-s` - Sync to server only
- `C-c C-l` - Load from server
- `C-c C-a` - Activate rule
- `C-c C-v` - Insert value block template
- `C-c C-t` - Insert rule template
- `TAB` - Complete protocol or value name

## Code Style Notes

- Function naming: `whistle--*` for internal, `whistle-*` for commands
- Error handling: `condition-case` with `user-error` for user-facing errors
- Messages: Use `message` with ✓/⚠️ prefixes for status feedback
- HTTP callbacks: Always provide error-callback parameter
- JSON parsing: Set `json-object-type` to `'alist` and `json-array-type` to `'list`
