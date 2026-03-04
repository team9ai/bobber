# Session Priority Design

**Date**: 2026-03-04
**Status**: Approved

## Overview

Add priority levels to sessions (Focus / Priority / Standard) with global sorting, project-level defaults, and per-session overrides.

## Priority Levels

| Level | Raw Value | Display | Description |
|-------|-----------|---------|-------------|
| Focus | 0 | 专注 | Highest priority, prominent visual treatment |
| Priority | 1 | 优先 | Elevated priority |
| Standard | 2 | 标准 | Default for all sessions |

## Data Model

### SessionPriority Enum

```swift
enum SessionPriority: Int, Codable, CaseIterable, Comparable {
    case focus = 0
    case priority = 1
    case standard = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### Session Changes

- Add `var priority: SessionPriority = .standard`
- Codable: missing field decodes as `.standard` (backward compatible)

### SessionManager Changes

- Add `@Published var projectPriorityDefaults: [String: SessionPriority]` (projectPath → priority)
- Persisted in `state.json`
- New sessions inherit priority from `projectPriorityDefaults[projectPath]` if set

## Sorting Logic (3-layer)

1. **Layer 1**: Group by priority (Focus → Priority → Standard)
2. **Layer 2**: Within same priority, group by projectPath
3. **Layer 3**: Within same project, sort by lastEvent descending

Between project groups at same priority level: sort by group's most recent lastEvent descending.

## UI

### List View (SessionsListView)

Priority group headers:
- Focus: "专注" with accent color (red/orange)
- Priority: "优先" with secondary color (blue/purple)
- Standard: no header displayed

Structure:
```
── 专注 ──
  ProjectA
    session1
    session2
── 优先 ──
  ProjectC
    session3
(no header)
  ProjectD
    session4
```

### Context Menu

**Session row**: Add "优先级" submenu → 专注 / 优先 / 标准 (checkmark on current)

**Project group header**: Add "设置项目优先级" submenu → 专注 / 优先 / 标准
- Immediately applies to all sessions in that project
- Updates `projectPriorityDefaults`

### Detail View (SessionDetailView)

Add priority picker (segmented control) in Status tab.

## Persistence

- `Session.priority` saved in `state.json` with session data
- `SessionManager.projectPriorityDefaults` saved in `state.json`
- Missing priority field on decode → defaults to `.standard`

## Edge Cases

1. **Upgrade**: Existing sessions without priority field decode as `.standard`
2. **Single vs project**: Per-session change only affects that session, not the project default
3. **Project default change**: Immediately updates all existing sessions at that projectPath + sets default for future sessions
4. **No sessions at priority level**: Priority group header not shown

## Out of Scope

- No changes to BobberEvent model or plugin
- No changes to config.json (priority is runtime state)
- No keyboard shortcuts for priority