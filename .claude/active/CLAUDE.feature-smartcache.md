# Feature Plan: Smart Cache - Project-Level Caching with Subfolder Extraction

## Overview

Cache entire project appraisals once, then extract subfolder contributions from cache on subsequent requests without calling the worker again.

## Current Architecture

```
Client → API → Check Redis cache (folder-specific key)
                  ↓ (hit)
              Return cached JSON
                  ↓ (miss)
              Send AppraisalRequest to SQS → Return 202 Processing
                                                  ↓
                                             Worker receives request
                                                  ↓
                                             Clone if needed
                                                  ↓
                                             Appraise FOLDER only
                                                  ↓
                                             Store JSON in Redis (folder key)
                                                  ↓
                                             Notify via Faye
```

**Current cache key format**: `appraisal:{owner}/{project}/{folder_path}`

**Problem**: Each subfolder requires a separate worker appraisal, even though:
- The worker clones the entire repo anyway
- Git blame runs on all files during appraisal
- Subfolder data is a subset of root appraisal data

## Proposed Architecture

```
Client → API → Check Redis cache (project root key)
                  ↓ (hit)
              Extract subfolder from cached root → Return JSON
                  ↓ (miss)
              Send AppraisalRequest to SQS (always root) → Return 202 Processing
                                                                ↓
                                                           Worker receives request
                                                                ↓
                                                           Clone if needed
                                                                ↓
                                                           Appraise ROOT folder
                                                                ↓
                                                           Store JSON in Redis (root key only)
                                                                ↓
                                                           Notify via Faye
```

**New cache key format**: `appraisal:{owner}/{project}/` (root only)

**Benefits**:
- Single worker request caches all subfolder data
- Subsequent subfolder requests are cache hits
- Reduced SQS messages, worker load, and latency

## Key Changes

### 1. Worker Changes

- **Modify**: Always appraise root folder (ignore folder_path in request)
- **Modify**: Cache key always uses root path (empty string)
- **Keep**: Progress reporting unchanged

### 2. Web API Changes

- **Add**: Subfolder extraction logic from cached root appraisal
- **Modify**: Cache lookup uses root key, then extracts subfolder
- **Modify**: AppraisalRequest always requests root (folder_path = "")
- **Add**: New domain/infrastructure for subfolder extraction

### 3. Cache Strategy

- **Single key per project**: `appraisal:{owner}/{project}/`
- **Value**: Full project `FolderContributions` JSON (root)
- **TTL**: 1 day (unchanged)
- **Extraction**: API extracts subfolder from cached root on demand

## Discussion Points

### Feasibility Assessment

**Pros:**

1. ⚠️ **Reduced worker calls**: One appraisal serves all subfolder requests
2. ⚠️ **Lower latency**: Subfolders served from cache after first request
3. ⚠️ **Simpler cache model**: One key per project vs many keys per folder
4. ⚠️ **Less SQS traffic**: Fewer worker requests

**Concerns to Address:**

1. ⚠️ **Cache size**: Root appraisal JSON larger than subfolder-only
   - Need to measure typical project JSON sizes
   - Redis memory implications

2. ⚠️ **Extraction complexity**: How to extract subfolder from root?
   - `FolderContributions` structure analysis needed
   - May need domain logic for subfolder filtering

3. ⚠️ **First request latency**: Root appraisal takes longer than subfolder
   - Acceptable tradeoff for subsequent speed

4. ⚠️ **Subfolder not found**: What if requested subfolder doesn't exist?
   - Need validation against cached structure

5. ⚠️ **Representer changes**: How to serialize extracted subfolder?
   - May need to reconstruct `FolderContributions` for subfolder

## Implementation Phases

### Phase 1: Analysis & Design

- [ ] Analyze `FolderContributions` structure for subfolder extraction
- [ ] Measure typical root appraisal JSON sizes
- [ ] Design subfolder extraction algorithm
- [ ] Decide on domain location for extraction logic
- [ ] Update this document with detailed design

### Phase 2: Worker Modifications

- [ ] Modify worker to always appraise root folder
- [ ] Update cache key generation (root only)
- [ ] Update tests for root-only behavior

### Phase 3: API Subfolder Extraction

- [ ] Create subfolder extraction logic
- [ ] Modify `FetchOrRequestAppraisal` service
- [ ] Handle subfolder-not-found errors
- [ ] Update tests for extraction behavior

### Phase 4: Cleanup & Testing

- [ ] Integration tests for full flow
- [ ] Performance comparison (before/after)
- [ ] Update CLAUDE.md documentation
- [ ] Cache migration strategy (if needed)

## Session Log

### Session 1

- Initial discussion of smart cache feature
- Updated CLAUDE.md to reflect current project state
- Created this planning document
- **Status**: Ready for feasibility discussion and planning

---

## Open Questions

1. How is `FolderContributions` structured? Can subfolders be extracted?
2. What is the typical JSON size for root vs subfolder appraisals?
3. Should extraction happen in domain layer or infrastructure?
4. How to handle deep nested paths efficiently?
5. Cache invalidation strategy unchanged?

---

## Decisions Made

### Decision 1: Navigate Cached Tree for Subfolder Extraction

- JSON preserves nested `FolderContributions` structure via recursive representer
- Subfolder extraction will **navigate the deserialized tree** (not filter/reconstruct)
- Extraction logic will likely reside in `Representer::FolderContributions` as a class method
- Tentative interface: `Representer::FolderContributions.extract_subfolder(json_string, folder_path)`
- **Rationale**: Representer already knows the JSON shape; keeps "shape knowledge" in one place
- *Details to be refined closer to implementation*

---

## Quick Reference

### Current Cache Key Format

```
appraisal:{owner}/{project}/{folder_path}
```

Examples:
- Root: `appraisal:ISS-SOA/codepraise-api/`
- Subfolder: `appraisal:ISS-SOA/codepraise-api/app/domain/`

### Proposed Cache Key Format

```
appraisal:{owner}/{project}/
```

Examples:
- All requests use: `appraisal:ISS-SOA/codepraise-api/`

### Key Files to Modify

**Worker:**

- `workers/application/services/appraise_project.rb`
- `app/domain/contributions/values/appraisal.rb`

**API:**

- `app/application/services/fetch_or_request_appraisal.rb`
- New: subfolder extraction logic (location TBD)

**Tests:**

- `spec/tests/unit/appraisal_spec.rb`
- `spec/tests/integration/services_spec.rb`

---

## Notes

### Commit Practices

- **Summarize changes before requesting commit permission** - provide brief summary by folder/file for user review BEFORE asking to commit
- **Separate concerns into distinct commits** - e.g., test setup changes vs feature changes
- **User is author, Claude is co-author** - use `Co-Authored-By: Claude <noreply@anthropic.com>`
- **Use conventional commit messages** - `feat:`, `fix:`, `refactor:`, `docs:`, etc.
  - `feat:` only for changes to external API/service features
  - `refactor:` for internal changes (new domain objects, infrastructure, etc.)

### Implementation Practices

- **Seek consent before moving to next phase** - summarize completed work, commit, then ask to proceed
- **Include coverage report in commits** - after successful tests, amend `coverage/.resultset.json` to coding commits

### Planning Practices

- **IMPORTANT: Pause after each question** - wait for explicit user approval before proceeding to the next question during planning discussions
