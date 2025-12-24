# Refactoring Plan: Progress Reporting Architecture (refactor-progress-reporting branch)

## Overview

Refactor the worker's progress reporting to use symbolic messages instead of numeric percentages, with a dedicated mapper translating symbols to percentages for Faye publication.

## Current Architecture

```
Service::AppraiseProject
    ↓ (numeric percentages: 15, 25, 50, 85, 100)
JobReporter.progress_callback
    ↓ (pass-through)
ProgressPublisher.publish
    ↓ (HTTP POST)
Faye Server → Client
```

**Current Issues:**

1. `Service::AppraiseProject` is tightly coupled to percentage values (15, 25, 50, etc.)
2. `JobReporter` is just a thin wrapper - doesn't add value beyond parsing job JSON
3. Percentage mapping logic is duplicated:
   - `AppraisalMonitor::PHASES` hash in `presentation/values/progress_monitor.rb`
   - Inline values in `Service::AppraiseProject` (15, 25, 40, 45, 50, 55, 85, 90, 100)
   - `scale_clone_progress` method also has its own mapping
4. Progress stages are not clearly named - just raw numbers
5. `CloneMonitor` is marked as "legacy" but still exists

## Proposed Architecture

```text
Worker Controller
    ↓ (deserializes job JSON, creates ProgressMapper)
Service::AppraiseProject
    ↓ (symbolic progress: :started, :clone_receiving, :appraising, etc.)
    ↓ (git output lines go through CloneMapper first)
ProgressMapper (in workers/infrastructure/faye/)
    ↓ (maps symbols → percentages)
FayeServer (in workers/infrastructure/faye/)
    ↓ (HTTP POST)
Faye Server → Client
```

**Key Changes:**

1. **Service sends symbols**: `progress.call(:started)` instead of `progress.call(15)`
2. **CloneMapper parses git output**: Converts git clone lines → symbols (`:clone_receiving`, etc.)
3. **ProgressMapper is single source of truth**: All symbol → percentage mappings in one place
4. **FayeServer is pure infrastructure**: Just HTTP POST, no business logic
5. **JobReporter eliminated**: Responsibilities split between controller (parsing) and ProgressMapper (reporting)

## Discussion Points

### Benefits

1. **Service is domain-focused**: Uses meaningful symbols like `:cloning`, `:appraising`
2. **Single source of truth**: All percentage mappings in one place (ProgressMapper)
3. **Testability**: Service tests don't need to know about percentages
4. **Flexibility**: Easy to change percentage distribution without touching service
5. **Clean architecture**: Proper layer separation (domain → presentation → infrastructure)

### Layer Placement

**Option A: Mapper in Presentation Layer**
- `workers/presentation/mappers/progress_mapper.rb`
- Aligns with current `progress_monitor.rb` location in presentation
- Translation from domain symbols to external format is a presentation concern

**Option B: Mapper in Application Layer**
- `workers/application/requests/progress_mapper.rb`
- Keeps request handling together (JobReporter was a request object)
- Application layer coordinates between domain and infrastructure

**Recommendation**: Option A - Presentation layer, because:
- Mapping domain concepts to external representation IS a presentation concern
- Similar to how Representers map entities to JSON
- Infrastructure (gateway) stays pure HTTP

### Symbol Design

**Current numeric stages in Service::AppraiseProject:**
```ruby
clone_repo:
  15  → STARTED
  50  → Skip clone (already exists)
  25, 35, 40, 45, 50 → Clone progress stages

appraise_contributions:
  55  → Starting appraisal
  85  → Appraisal complete

cache_result:
  90  → Caching
  100 → FINISHED
```

**Proposed symbols:**
```ruby
# Main phases
:started           # 15 - Worker began processing
:clone_started     # 20 - Beginning clone
:clone_receiving   # 40 - Receiving objects from remote
:clone_resolving   # 45 - Resolving deltas
:clone_done        # 50 - Clone complete (or skipped)
:appraise_started  # 55 - Beginning git blame analysis
:appraise_done     # 85 - Analysis complete
:cache_started     # 90 - Storing in Redis
:finished          # 100 - All done
```

### Git Clone Progress Handling

**Current approach**: `scale_clone_progress(line)` parses git output and maps keywords:
```ruby
{ 'Cloning' => 25, 'remote' => 35, 'Receiving' => 40, 'Resolving' => 45, 'Checking' => 50 }
```

**Options:**

A. **Keep in Service**: Service parses git output, sends fine-grained symbols
B. **Move to Mapper**: Service sends `:clone_progress` with raw line, mapper parses
C. **Simplify**: Only report major phases, skip line-by-line git progress

**Recommendation**: Option C - Simplify. The line-by-line progress adds complexity without significant UX benefit. Report: `:clone_started`, `:clone_done`.

## Implementation Phases

### Phase 1: Restructure Faye Infrastructure ✅

**Rename folder**: `workers/infrastructure/messaging/` → `workers/infrastructure/faye/`

**Rename file**: `progress_publisher.rb` → `faye_server.rb`

- [x] Rename class `ProgressPublisher` → `FayeServer`
- [x] Keep same interface: `publish(message)`
- [x] This is pure infrastructure - no logic changes

**New file**: `workers/infrastructure/faye/progress_mapper.rb`

- [x] Create `Appraiser::ProgressMapper` class
- [x] Define `PHASES` hash (single source of truth for all symbol → percentage mappings)
- [x] Include all phases: `:started`, `:clone_receiving`, `:clone_resolving`, `:clone_done`, `:appraising`, `:appraise_done`, `:caching`, `:finished`
- [x] Implement `map(symbol) → percentage` method
- [x] Accept FayeServer in constructor for dependency injection
- [x] Implement `report(symbol)` that maps and publishes via FayeServer

**New file**: `workers/infrastructure/git/mappers/clone_mapper.rb`

- [x] Create `CloneMapper` module
- [x] Parse git clone output lines into symbols
- [x] Map: `"Receiving..."` → `:clone_receiving`, `"Resolving..."` → `:clone_resolving`, etc.
- [x] Return symbol that ProgressMapper can translate to percentage

### Phase 2: Update Service to Use Symbols

**Modify**: `workers/application/services/appraise_project.rb`

- [ ] Change all `input[:progress].call(15)` → `input[:progress].call(:started)`
- [ ] Remove `scale_clone_progress` method
- [ ] Use CloneMapper to convert git output lines to symbols
- [ ] Use symbols throughout: `:started`, `:clone_receiving`, `:clone_done`, `:appraising`, etc.

### Phase 3: Update Worker Controller

**Modify**: `workers/application/controllers/worker.rb`

- [ ] Move job JSON deserialization from JobReporter to controller
- [ ] Create ProgressMapper with FayeServer and channel_id
- [ ] Pass `progress_mapper.progress_callback` to service
- [ ] Update `report_each_second` logic to use ProgressMapper with `:finished` symbol

### Phase 4: Cleanup

- [ ] Delete `workers/application/requests/job_reporter.rb`
- [ ] Delete `workers/presentation/values/progress_monitor.rb`
  - `CloneMonitor` module (marked as legacy)
  - `AppraisalMonitor` module (replaced by ProgressMapper)
- [ ] Update `require_worker.rb` for new file locations
- [ ] Update tests for new symbol-based interface

## Open Questions

1. ~~Should we keep fine-grained git clone progress, or simplify to just start/done?~~ **DECIDED: Keep fine-grained via CloneMapper**
2. ~~JobReporter: combine with ProgressMapper, or keep separate?~~ **DECIDED: Eliminate JobReporter, merge reporting into ProgressMapper**
3. ~~Should ProgressMapper be in presentation or application layer?~~ **DECIDED: Infrastructure (with FayeServer)**
4. ~~Keep AppraisalMonitor::PHASES as the source of truth, or define in ProgressMapper?~~ **DECIDED: ProgressMapper is the single source of truth**

All open questions resolved!

---

## Decisions Made

### Decision 1: Infrastructure Gateway Naming

- Rename `ProgressPublisher` → `FayeServer`
- File: `workers/infrastructure/messaging/progress_publisher.rb` → `faye_server.rb`
- **Rationale**: "Server" better describes the role as an infrastructure gateway to the Faye server

### Decision 2: Faye Infrastructure Organization

- Rename folder: `workers/infrastructure/messaging/` → `workers/infrastructure/faye/`
- Place both `FayeServer` (gateway) and `ProgressMapper` (mapper) in this folder
- Structure:

  ```text
  workers/infrastructure/faye/
  ├── faye_server.rb      # Gateway - HTTP POST to Faye
  └── progress_mapper.rb  # Mapper - symbols → percentages
  ```

- **Rationale**: Faye is infrastructure; the mapper translates domain symbols for this specific infrastructure concern. Keeping gateway + mapper together follows the pattern in `workers/infrastructure/git/` (gateway + mappers)

### Decision 4: Eliminate JobReporter

- Delete `workers/application/requests/job_reporter.rb`
- Move job JSON deserialization to Worker controller (or service's first step)
- Move `report()`, `report_each_second()`, `progress_callback()` to ProgressMapper
- **Rationale**: JobReporter has no distinct responsibility:
  - Its reporting methods belong in ProgressMapper
  - Its JSON deserialization is trivial (3 lines) and can live in controller/service

**Before:**
```text
Worker.perform(request_json)
    ↓
JobReporter.new(request_json, config)  # parses + creates publisher
    ↓
Service::AppraiseProject.call(progress: job.progress_callback)
```

**After:**
```text
Worker.perform(request_json)
    ↓
Deserialize job (in controller or service step)
    ↓
ProgressMapper.new(config, channel_id)  # created with FayeServer
    ↓
Service::AppraiseProject.call(progress: mapper.progress_callback)
```

### Decision 5: Symbol Naming Convention

- Use `-ing` suffix for ongoing action phases: `cloning_*`, `appraising_*`, `caching_*`
- Symbols: `:started`, `:cloning_started`, `:cloning_remote`, `:cloning_receiving`, `:cloning_resolving`, `:cloning_done`, `:appraising_started`, `:appraising_done`, `:caching_started`, `:finished`
- **Rationale**: Consistent naming that describes ongoing actions; more readable and descriptive

### Decision 3: Git Clone Progress with CloneMapper

- Create `CloneMapper` to parse git clone output lines into symbols
- Location: `workers/infrastructure/git/mappers/clone_mapper.rb` (alongside other git mappers)
- `CloneMapper` converts git output → symbols (`:clone_receiving`, `:clone_resolving`, etc.)
- `ProgressMapper` remains the single source of truth for all symbol → percentage mappings
- Flow:

  ```text
  Git clone output line (e.g., "Receiving objects: 50%...")
      ↓
  CloneMapper.map(line) → :clone_receiving
      ↓
  ProgressMapper.report(:clone_receiving) → 40%
      ↓
  FayeServer.publish("40")
  ```

- **Rationale**: Separates concerns - git parsing stays with git infrastructure, percentage mapping stays centralized in ProgressMapper

---

## Session Log

### Session 1

- Initial discussion of refactoring goals
- Created this planning document
- Reviewed current architecture:
  - `workers/application/requests/job_reporter.rb` - thin wrapper around ProgressPublisher
  - `workers/infrastructure/messaging/progress_publisher.rb` - HTTP POST to Faye
  - `workers/application/services/appraise_project.rb` - uses numeric percentages
  - `workers/presentation/values/progress_monitor.rb` - CloneMonitor (legacy) + AppraisalMonitor
- Identified issues:
  - Duplicate percentage mappings in multiple places
  - Service coupled to numeric values
  - JobReporter adds little value
- **Status**: Initial planning, awaiting user feedback on proposed approach

---

## Notes

### Post-Implementation Cleanup

After final implementation and testing:

- [ ] Add `CLAUDE.refactor-progress-reporting.md` to `.gitignore`
- [ ] Move this file to `.claude/_archive/CLAUDE.refactor-progress-reporting.md`

### Commit Practices

- **Summarize changes before requesting commit permission** - provide brief summary by folder/file for user review BEFORE asking to commit
- **Separate concerns into distinct commits** - e.g., infrastructure rename vs service logic changes
- **User is author, Claude is co-author** - use `Co-Authored-By: Claude <noreply@anthropic.com>`
- **Use conventional commit messages** - `feat:`, `fix:`, `refactor:`, `docs:`, etc.
  - `refactor:` for internal changes (this refactoring)
  - `feat:` only for changes to external API/service features

### Implementation Practices

- **Seek consent before moving to next phase** - summarize completed work, commit, then ask to proceed
- **Include coverage report in commits** - after successful tests, amend `coverage/.resultset.json` to coding commits
