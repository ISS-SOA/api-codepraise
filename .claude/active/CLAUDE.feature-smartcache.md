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

1. ~~⚠️ **Cache size**: Root appraisal JSON larger than subfolder-only~~ **RESOLVED: ~30KB is practical**

2. ~~⚠️ **Extraction complexity**: How to extract subfolder from root?~~ **RESOLVED: Navigate tree via Roar deserialization**

3. ~~⚠️ **First request latency**: Root appraisal takes longer than subfolder~~ **ACCEPTED: Same as current (full clone happens anyway)**

4. ⚠️ **Subfolder not found**: What if requested subfolder doesn't exist?
   - Return nil from extraction, service returns 404

5. ~~⚠️ **Representer changes**: How to serialize extracted subfolder?~~ **RESOLVED: Re-serialize OpenStruct subtree via representer**

## Implementation Phases

### Phase 1: Analysis & Design ✅

- [x] Analyze `FolderContributions` structure for subfolder extraction
- [x] Measure typical root appraisal JSON sizes (~30KB practical)
- [x] Design subfolder extraction algorithm (tree traversal via Roar deserialization)
- [x] Decide on location for extraction logic (Representer)
- [x] Document decisions in this file

### Phase 2: Refactor - Create `Request::AppraisalRequest`

**Replace `Request::ProjectPath` with `Request::AppraisalRequest`:**

- [ ] Create `Request::AppraisalRequest` in `app/application/requests/`
  - Subsumes `ProjectPath` functionality (owner_name, project_name, folder_name)
  - Add `project_fullname` method
  - Add `root_cache_key` method (`appraisal:{owner}/{project}/`)
  - Add `folder_cache_key` method (`appraisal:{owner}/{project}/{folder}`)
  - Add `root_request?` helper
- [ ] Update controller to use `Request::AppraisalRequest` instead of `ProjectPath`
- [ ] Update `Service::FetchOrRequestAppraisal` to use request's cache key methods
- [ ] Remove duplicate `appraisal_cache_key` helper from service
- [ ] Delete old `Request::ProjectPath` (or keep as alias if needed)
- [ ] Update/add unit tests for `Request::AppraisalRequest`
- [ ] Verify all existing tests pass (no behavior change yet)

### Phase 3: Representer Subfolder Extraction

**Add extraction methods to `Representer::FolderContributions`:**

- [ ] Add `find_subfolder(root_ostruct, folder_path)` - tree traversal helper
- [ ] Add `extract_subfolder(json_string, folder_path)` - returns OpenStruct or nil
- [ ] Add `extract_subfolder_json(json_string, folder_path)` - returns JSON string or nil
- [ ] Handle edge cases: root path (empty string), path not found, trailing slashes
- [ ] Unit tests for extraction methods

### Phase 4: Worker Modifications

**Modify worker to always appraise root folder:**

- [ ] Update `Appraiser::Service::AppraiseProject` to ignore folder_path, always appraise root
- [ ] Update `Value::Appraisal#cache_key` for root-only behavior
- [ ] Update worker unit tests

### Phase 5: API Service Modifications

**Modify `FetchOrRequestAppraisal` to use smart cache:**

- [ ] Change cache lookup to use `request.root_cache_key`
- [ ] On cache hit: extract requested subfolder from cached root JSON
- [ ] Handle subfolder-not-found (return 404)
- [ ] On cache miss: send AppraisalRequest (worker will appraise root)
- [ ] Update service unit/integration tests

### Phase 6: Cleanup & Testing

- [ ] End-to-end acceptance tests for smart cache flow
- [ ] Test scenarios: root request, subfolder request, nested subfolder, invalid path
- [ ] Verify old folder-specific cache keys are ignored (TTL expiration)
- [ ] Update `.claude/CLAUDE.md` documentation with new architecture
- [ ] Update session log with completion status

## Session Log

### Session 1

- Initial discussion of smart cache feature
- Updated CLAUDE.md to reflect current project state
- Created this planning document
- Answered all 6 Open Questions:
  - Q1: FolderContributions has nested tree structure; JSON preserves it via recursive representer
  - Q2: Measured JSON sizes (~30KB for root project); root-only caching is practical
  - Q3: Extraction logic in Representer (presentation layer) - keeps entity worker-only
  - Q4: Tree traversal is O(depth); Roar `from_json` handles nested deserialization automatically
  - Q5: Cache invalidation unchanged; smart cache simplifies (one key per project)
  - Q6: Create `Request::AppraisalRequest` subsuming `ProjectPath` with cache key methods
- Made 5 decisions (see Decisions Made section)
- Refined Implementation Phases (6 phases) with Phase 2 as AppraisalRequest refactor
- Committed: `a8c21df` - docs: reorganize Claude documentation and add feature planning
- **Status**: Phase 1 (Analysis & Design) COMPLETE; ready for Phase 2

---

## Open Questions

1. ~~How is `FolderContributions` structured? Can subfolders be extracted?~~ **ANSWERED: See Decision 1**
2. ~~What is the typical JSON size for root vs subfolder appraisals?~~ **ANSWERED: ~30KB root; practical for Redis**
3. ~~Should extraction happen in domain layer or infrastructure?~~ **ANSWERED: See Decision 2**
4. ~~How to handle deep nested paths efficiently?~~ **ANSWERED: See Decision 3**
5. ~~Cache invalidation strategy unchanged?~~ **ANSWERED: See Decision 4**
6. ~~Should cache-key generation be consolidated with request parsing?~~ **ANSWERED: See Decision 5**

---

## Decisions Made

### Decision 1: Navigate Cached Tree for Subfolder Extraction

- JSON preserves nested `FolderContributions` structure via recursive representer
- Subfolder extraction will **navigate the deserialized tree** (not filter/reconstruct)
- **Rationale**: Leverages existing JSON structure; no reconstruction needed

### Decision 2: Extraction Logic in Presentation Layer (Representer)

- Extraction logic will reside in `Representer::FolderContributions` as class methods
- Tentative interface:
  - `extract_subfolder(json_string, folder_path)` → OpenStruct or nil
  - `extract_subfolder_json(json_string, folder_path)` → JSON string or nil
- **Rationale**:
  - Representer already knows the JSON shape
  - This is representation logic, not business logic
  - Keeps service layer thin
  - Avoids needing `FolderContributions` entity in API (stays worker-only)
- Alternative considered: Domain entity - rejected because (a) would require API to have the entity, (b) extraction is representation concern not business logic
- **⚠️ Concern noted**: Representer-based traversal may be brittle to changes in the entity structure. If `FolderContributions` entity changes how it organizes subfolders or paths, the representer extraction logic could break. If this becomes an issue, reconsider having the entity own the traversal logic (would require sharing entity between API and worker).

### Decision 3: Roar Deserialization is Sufficient

- Roar's `from_json` already handles nested deserialization automatically
- Deserializes to `OpenStruct` tree (not domain entities) - sufficient for traversal
- No mapper needed (JSON → Entity conversion would be extra work with no benefit)
- API only needs to pass through JSON to client; OpenStruct sufficient for subfolder lookup
- **Verified**: Tested with cached `YPBT-app` project - full nested tree deserializes correctly

### Decision 4: Cache Invalidation Strategy Unchanged

- TTL-based expiration remains: 1 day for success, 10 seconds for errors
- Manual wipe via `rake cache:wipe` unchanged
- Smart cache **simplifies** invalidation: one key per project instead of many
- No automatic invalidation on repo updates (deferred to future feature)
- **Future considerations** (out of scope for this feature):
  - Webhook-based invalidation on GitHub push
  - Manual wipe + re-appraisal workflow

### Decision 5: Create `Request::AppraisalRequest` Subsuming `ProjectPath`

- New `Request::AppraisalRequest` object will replace `Request::ProjectPath`
- Owns cache key generation as single source of truth
- Provides:
  - `owner_name`, `project_name`, `folder_name` (from ProjectPath)
  - `project_fullname` method
  - `root_cache_key` method (`appraisal:{owner}/{project}/`)
  - `folder_cache_key` method (`appraisal:{owner}/{project}/{folder}`)
  - `root_request?` helper
- **Rationale**:
  - Semantic clarity: Request (what is asked for) vs Appraisal (result of work)
  - Removes duplicate cache key logic from service
  - Centralizes "what is being requested" concept
  - Awkward to call `Value::Appraisal` before appraisal work is done
- **Implementation**: Refactor in Phase 2 before smart cache feature work
- **Note**: `Value::Appraisal#cache_key` remains for worker use (result caching)

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
