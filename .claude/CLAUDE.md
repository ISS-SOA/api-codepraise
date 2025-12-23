# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CodePraise Web API** is a RESTful JSON API that analyzes GitHub repositories to generate "praise reports" showing individual contributor contributions to team projects. It pulls data from GitHub's API, clones repos, and analyzes git blame information to assess contributions.

This is a **Web API only** - there is NO web interface. All responses are JSON. A separate frontend application consumes this API.

## Common Development Commands

### Setup
```bash
bundle install
cp config/secrets_example.yml config/secrets.yml  # Add your GitHub token
bundle exec rake db:migrate                        # Dev database
RACK_ENV=test bundle exec rake db:migrate          # Test database
```

### Cache Setup (Required)

Redis is required for caching appraisal results. Environment isolation via separate Redis databases:

- Development: `redis://localhost:6379/0`
- Test: `redis://localhost:6379/1`
- Production: as assigned by provider

```bash
rake cache:redis:start       # Start Redis Docker container
rake cache:redis:stop        # Stop Redis Docker container
rake cache:status            # Check cache connectivity
rake cache:ensure            # Start if not running (used by rake spec)
rake cache:list              # List all cached keys
rake cache:wipe              # Wipe all cached keys
```

**Note:** `rake spec` automatically ensures cache is running before tests.

### Testing
```bash
rake spec                    # Run all tests (unit + integration only)
bash spec/acceptance_tests   # Run full test suite with worker (recommended)
rake respec                  # Continuously run tests on file changes
```

**Important:** Acceptance tests require both API and worker running. Use `bash spec/acceptance_tests` which starts the worker automatically.

### Running the Application
```bash
rake run                     # Start Puma web server
rake rerun                   # Auto-restart on file changes
rake console                 # Launch Pry console with app loaded
```

### Background Worker (Development)
```bash
rake worker:run:dev          # Run Shoryuken worker in development mode
rake worker:run:test         # Run worker in testing mode
rake worker:run:production   # Run worker in production mode
```

### Queue Management
```bash
rake queues:create           # Create SQS queue for worker
rake queues:status           # Report status of worker queue
rake queues:purge            # Purge all messages from queue
```

### Database Management
```bash
rake db:migrate              # Run database migrations
rake db:wipe                 # Clear all data from tables (dev/test only)
rake db:drop                 # Delete database file (dev/test only)
```

### Repository Store Management

```bash
rake repos:create            # Create directory for repo store
rake repos:list              # List cloned repos in repo store
rake repos:wipe              # Delete all cloned repos
```

### Code Quality
```bash
rake quality:all             # Run all quality checks (rubocop + reek + flog)
rake quality:rubocop         # Code style linter
rake quality:reek            # Code smell detector
rake quality:flog            # Complexity analysis
```

### Test Fixtures
```bash
rake vcr:wipe               # Delete VCR cassettes (recorded HTTP fixtures)
```

## API Endpoints

### Root check
`GET /`
- **200**: API server running (returns API version and environment info)

### Appraise a previously stored project
`GET /api/v1/projects/{owner_name}/{project_name}[/{folder_path}]`
- **200**: Appraisal returned (JSON with project and folder contributions)
- **404**: Project or folder not found
- **500**: Problems finding or cloning GitHub project

### Store a project for appraisal
`POST /api/v1/projects/{owner_name}/{project_name}`
- **201**: Project stored (returns project JSON)
- **404**: Project not found on GitHub
- **500**: Problems storing the project

### Get list of projects
`GET /api/v1/projects?list={base64_encoded_json_array}`
- **200**: List of projects returned (JSON array)
- **400**: Missing or invalid list parameter

## Architecture

This application uses **Clean Architecture / Enterprise Design Patterns** with strict layer separation:

### 4-Layer Web API Architecture

```
WEB LAYER (Controllers)
    ↓
APPLICATION LAYER (Services + Requests + Responses)
    ↓
INFRASTRUCTURE LAYER (Database, GitHub Gateway, Git Gateway, Mappers, Cache, Messaging)
    ↓
DOMAIN LAYER (Entities + Values)
```

### Worker-Based Appraisal Architecture

Appraisal requests are processed asynchronously via background workers with Redis caching:

```
Client Request
    ↓
API: Check Redis cache
    ↓ (hit)
Return cached JSON ──→ Client
    ↓ (miss)
Send AppraisalRequest to SQS → Return 202 Processing
    ↓
Worker receives request
    ↓
Clone repo (if needed) → Appraise folder → Store JSON in Redis
    ↓
Notify via Faye (progress updates)
    ↓
Client polls API → Cache hit → Return result
```

**Key features:**
- **Redis as primary cache**: Worker stores serialized JSON with 1-day TTL
- **No Rack::Cache for appraisals**: Redis is the source of truth
- **Worker does all heavy lifting**: Clone + git blame + serialization
- **API is lightweight**: Just checks cache and dispatches requests

**Key architectural change**: The PRESENTATION layer has been restructured for Web API:
- **NO HTML views or view objects** - removed entirely
- **Representers** use Roar gem to serialize domain entities to JSON
- **Responses** are simple data structures passed between layers

### Layer Responsibilities

**1. Domain Layer (`app/domain/`)**

Organized into bounded contexts with **immutable value objects** using `Dry::Struct`:

**Projects Context (`app/domain/projects/`):**
- `Entity::Project`: Aggregate root for projects with owner and contributors
- `Entity::Member`: GitHub user/contributor entity
- Pure business logic with type-safe attributes
- Entities include `to_attr_hash` method for persistence

**Contributions Context (`app/domain/contributions/`):**

- `Value::Appraisal`: Immutable result of appraising a folder (success or error)
  - Located in API domain as it's used by both API and worker
  - Uses `Nominal(Object)` type for folder attribute (duck typing)

**Contributions Context (`workers/domain/contributions/`):**
- `Entity::FolderContributions`: Aggregate root for folder-level contributions
- `Entity::FileContributions`: File-level code contributions
- `Entity::LineContribution`: Individual line attribution
- `Entity::Contributor`: Contributor in context of code analysis
- `Value::CreditShare`: Credits shared by contributors (using SimpleDelegator)
- `Value::FilePath`: Value object for file path operations
- `Value::CodeLanguage`: Programming language identification
- `Value::Contributors`: Collection of contributors with identity grouping logic
- `Mixins::ContributionsCalculator`: Shared calculation logic
- These entities/values are worker-only (git blame analysis)

**Domain Characteristics:**
- **No database or framework dependencies**
- Type-safe with `Dry::Types` (`Strict::String`, `Strict::Integer`, etc.)
- Custom types in `lib/types.rb` (e.g., `HashedArrays`, `HashedIntegers`)

**2. Infrastructure Layer (`app/infrastructure/`)**

**Database (`app/infrastructure/database/`):**
- **ORM Models** (`orm/`): Thin Sequel models defining table relationships
  - `ProjectOrm`: `many_to_one :owner`, `many_to_many :contributors`
  - `MemberOrm`: `one_to_many :owned_projects`, join table relationships
- **Repositories** (`repositories/`): Persistence logic
  - `Projects`: CRUD operations for projects
  - `Members`: CRUD operations for members
  - `For`: Polymorphic router mapping entity types to repositories
  - Pattern: `Repository::For.entity(project).create(project)`
  - Pattern: `Repository::For.klass(Entity::Project).find_full_name(owner, name)`

**Cache (`app/infrastructure/cache/`):**

- **Redis Cache Client** (`Cache::Remote`): Redis client wrapper for appraisal caching
  - `get(key)`, `set(key, value, ttl:)`, `exists?(key)` methods
  - Environment isolation via separate Redis databases (no key prefixes)
  - Appraisal cache keys: `appraisal:{owner}/{project}/{folder}`
- Development: Local Redis (`redis://localhost:6379/0`)
- Test: Local Redis (`redis://localhost:6379/1`)
- Production: Redis cloud cache (as assigned by provider)

**GitHub Integration (`app/infrastructure/github/`):**
- **Gateway** (`Api`): Authenticated HTTP requests to GitHub API
- **Mappers** (`mappers/`): Transform API responses into domain entities
  - `ProjectMapper`: GitHub JSON → `Entity::Project`
  - `MemberMapper`: GitHub JSON → `Entity::Member`

**Messaging (`app/infrastructure/messaging/`):**
- **Queue** (`queue.rb`): AWS SQS queue wrapper
  - Sends clone requests to background worker
  - Polls queue for messages (used by worker)
  - Requires AWS credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`

**3. Application Layer (`app/application/`)**

**Services (`app/application/services/`):**

- Use **Dry::Transaction** for composable service pipelines
- `AddProject`: Fetches project from GitHub and stores in database
  - Steps: `validate_project`, `store_project`
- `FetchOrRequestAppraisal`: Checks Redis cache, dispatches to worker if miss
  - Steps: `find_project_details`, `check_project_eligibility`, `check_cache`, `request_appraisal_worker`
  - Cache hit: Returns pre-serialized JSON from Redis
  - Cache miss: Sends AppraisalRequest to SQS, returns `processing` status
- `ListProjects`: Returns list of stored projects
  - Steps: `validate_list`, `retrieve_list`

**Requests (`app/application/requests/`):**
- `ProjectPath`: Parses route parameters for project appraisal
- `EncodedProjectList`: Encodes/decodes base64 JSON project lists

**Responses (`app/application/responses/`):**

- `ApiResult`: Standard API response wrapper (status + message)
- `ProjectsList`: Struct for list of projects

**Controllers (`app/application/controllers/`):**
- `App`: Main Roda application with routing
- `Helpers`: Controller helper methods
- Routes use services, not direct database access
- All responses are JSON via representers

**4. Presentation Layer (`app/presentation/`)**

**Representers (`app/presentation/representers/`):**

- Use **Roar** gem for JSON serialization (not HTML views)
- `HttpResponse`: HTTP status code + JSON response wrapper
- `Project`: Serializes `Entity::Project` to JSON with hypermedia links
- `ProjectsList`: Serializes collection of projects
- `Appraisal`: Serializes `Value::Appraisal` with status wrapper (used by worker)
- `AppraisalRequest`: Serializes request payload sent to worker via SQS
- `FolderContributions`: Serializes folder-level contributions
- `FileContributions`: Serializes file-level contributions
- `Contributor`: Serializes contributor data
- `Member`: Serializes member/owner data
- `LineContribution`: Serializes line-level attribution
- `CreditShare`: Serializes credit distribution
- `FilePath`: Serializes file path information
- `OpenStructWithLinks`: Helper for hypermedia links

**Responses (`app/presentation/responses/`):**

- Simple data structures for passing between layers
- `CloneRequest`: Legacy request format for clone-only operations
- `AppraisalRequest`: Request format with full project info + folder path

**Key differences from traditional web app:**
- **NO HTML templates** (no Slim views)
- **NO view objects** (no presentation logic wrappers)
- **NO static assets** (CSS, JavaScript, images)
- Representers provide JSON serialization only
- Hypermedia links embedded in JSON responses

### Key Architectural Patterns

**Bounded Contexts (DDD):**
- Domain organized into **Projects** and **Contributions** contexts
- Each context has its own entities, values, and domain logic
- Contexts can share some entities (e.g., `Member`/`Contributor`)
- Clear separation of concerns within the domain layer

**Service Layer with Dry::Transaction:**
- Services composed of discrete steps
- Each step returns `Success(data)` or `Failure(error)`
- Railway-oriented programming for error handling
- Steps are private methods in service classes

**Repository Pattern with Polymorphic Routing:**
```ruby
# Generic entity-based routing
Repository::For.entity(project).create(project)
Repository::For.klass(Entity::Project).find_full_name(owner, name)
```

**Data Mapper Pattern:**
- Multiple mapper types transform external data to domain entities:
  - GitHub mappers: API JSON → domain entities
  - Git mappers: git commands/porcelain output → domain entities
- Dependency injection for testability (pass gateway as parameter)

**Gateway Pattern:**
- `Github::Api`: Wraps HTTP communication with GitHub API
- `Git::GitCommand`: Wraps git command-line operations
- Gateways handle external system complexity and failure modes

**Representer Pattern (Roar):**
- Presentation layer uses representers to serialize domain entities to JSON
- Representers handle hypermedia links (HATEOAS)
- Clear separation: domain entities remain unaware of JSON serialization

**Appraisal Caching (Redis):**

- Worker stores serialized JSON in Redis with TTL
- API reads cached results directly (no re-serialization)
- Cache key format: `appraisal:{owner}/{project}/{folder}`
- Success TTL: 1 day (86400 seconds)
- Error TTL: 10 seconds (allows quick retry)

**Immutable Value Objects:**
- Domain entities are immutable via `Dry::Struct`
- Value objects use `SimpleDelegator` for specialized collections
- No accidental mutation of business logic

### Background Worker Architecture

The application uses **Shoryuken** with **AWS SQS** for asynchronous appraisal operations and **Faye** for real-time progress updates via websockets.

The worker has its own **DDD-style layer structure** parallel to the API:

```text
workers/
├── domain/contributions/           # Entities, values, lib for git analysis
├── infrastructure/
│   ├── git/                        # Git gateway, repositories, mappers
│   └── messaging/                  # Faye progress publisher
├── presentation/values/            # Progress monitor calculations
├── application/
│   ├── controllers/worker.rb       # Shoryuken entry point
│   ├── services/appraise_project.rb
│   └── requests/job_reporter.rb
└── shoryuken*.yml                  # Queue configs
```

**Worker Application Layer (`workers/application/`):**

- `controllers/worker.rb`: Main Shoryuken worker class (`Appraiser::Worker`)
  - Receives AppraisalRequest from SQS queue
  - Dispatches to `Appraiser::Service::AppraiseProject` service
  - Reports progress via Faye websockets

- `services/appraise_project.rb`: Worker service (`Appraiser::Service::AppraiseProject`)
  - Dry::Transaction pipeline: `prepare_inputs` → `clone_repo` → `appraise_contributions` → `cache_result`
  - Clones repo if not exists locally
  - Runs git blame analysis via `Mapper::Contributions`
  - Stores serialized JSON in Redis with TTL

- `requests/job_reporter.rb`: Manages progress reporting
  - Deserializes AppraisalRequest from JSON
  - Publishes progress updates to Faye channel

**Worker Infrastructure Layer (`workers/infrastructure/`):**

- `git/gateway/git_command.rb`: Execute git commands on local repos
- `git/repositories/`: Git repository operations
  - `GitRepo`: Factory for local/remote repo handling
  - `LocalRepo`: Manages cloned local repositories
  - `RemoteRepo`: Clones remote repos to local storage
  - `BlameReporter`: Runs git blame to get line-by-line attribution
  - `RepoFile`: Represents individual files in repo
- `git/mappers/`: Transform git data into domain entities
  - `ContributionsMapper`: Orchestrates full contribution analysis
  - `FolderContributionsMapper`: Maps folder structure to `Entity::FolderContributions`
  - `FileContributionsMapper`: Maps file data to `Entity::FileContributions`
  - `BlameContributor`: Maps git contributor info to `Entity::Contributor`
  - `PorcelainParser`: Parses git blame porcelain format
- `messaging/progress_publisher.rb`: Sends progress to Faye
  - POSTs JSON messages to `/faye` endpoint
  - Channel format: `/{request_id}`

**Worker Presentation Layer (`workers/presentation/`):**

- `values/progress_monitor.rb`: Tracks progress phases
  - `AppraisalMonitor`: Full appraisal progress (15-50% clone, 55-85% appraise, 90-100% cache)

**Configuration Files:**

- `workers/shoryuken.yml`: Production SQS queue URL
- `workers/shoryuken_dev.yml`: Development queue configuration
- `workers/shoryuken_test.yml`: Test queue configuration

**Code Loading:**

- `require_app.rb`: Loads API layers (domain, infrastructure, presentation, application)
- `require_worker.rb`: Loads worker layers (domain, infrastructure, presentation, application)

**Websocket Integration (Faye):**

The web server mounts Faye at `/faye` (configured in `config.ru`):
```ruby
use Faye::RackAdapter, mount: '/faye', timeout: 25
```

Frontend clients subscribe to channels matching their `request_id` to receive real-time progress updates.

**Async Request Flow:**

```
1. Client requests appraisal → API generates unique request_id
2. API checks Redis cache for existing result
3. If cache hit: return cached JSON immediately (200)
4. If cache miss:
   - API sends AppraisalRequest to SQS queue
   - API returns 202 Processing with request_id
   - Client subscribes to Faye channel /{request_id}
5. Worker picks up job from SQS
6. Worker clones repo (if needed) → appraises → caches in Redis
7. Progress sent to Faye (15-50% clone, 55-85% appraise, 90-100% cache)
8. Client retries appraisal request after receiving 100%
9. API returns cached result (200)
```

**Required Environment Variables (for worker):**

- `AWS_ACCESS_KEY_ID`: AWS credentials for SQS
- `AWS_SECRET_ACCESS_KEY`: AWS credentials for SQS
- `AWS_REGION`: AWS region (e.g., `us-east-1`)
- `WORKER_QUEUE_URL`: Full SQS queue URL
- `REDIS_URL`: Redis URL for caching results (e.g., `redis://localhost:6379/0`)
- `API_HOST`: API base URL for Faye endpoint (e.g., `https://api.example.com`)

### Data Flow Examples

**Adding a GitHub project:**
```
POST /api/v1/projects/{owner}/{name}
  ↓
Controller → Service::AddProject.call(owner_name:, project_name:)
  ↓
Service steps:
  1. validate_project (check if already exists)
  2. find_project → Github::ProjectMapper.find(owner, name)
     - ProjectMapper → Github::Api.repo_data() [HTTP call]
     - Builds Entity::Project from API response
  3. store_project → Repository::For.entity(project).create(project)
     - Find/create owner Member in DB
     - Create Project record
     - Find/create Contributor Members
     - Link via projects_members join table
  ↓
Controller receives Success(ApiResult) or Failure(ApiResult)
  ↓
Representer::HttpResponse wraps result
  ↓
Representer::Project.new(project).to_json
  ↓
JSON response with 201 status
```

**Viewing project contributions:**

```
GET /api/v1/projects/{owner}/{name}[/{folder}]
  ↓
Controller → Request::ProjectPath parses route parameters
  ↓
Controller → Service::FetchOrRequestAppraisal.call(requested: path_request)
  ↓
Service steps:
  1. find_project_details
     - Repository::For.klass(Entity::Project).find_full_name(owner, name)
     - Returns Failure(:not_found) if not in database
  2. check_project_eligibility
     - Rejects projects that are too large
  3. check_cache
     - Cache::Remote.get(cache_key)
     - If hit: return pre-serialized JSON immediately
  4. request_appraisal_worker (cache miss only)
     - Send AppraisalRequest to SQS with full project info
     - Return Failure(:processing) with request_id
  ↓
Controller receives Success or Failure
  ↓
Cache hit: Return cached JSON directly (200)
Cache miss: Return 202 Processing with request_id
```

**Worker processes appraisal (async):**

```
Worker receives AppraisalRequest from SQS
  ↓
Appraiser::Service::AppraiseProject steps:
  1. prepare_inputs - convert OpenStruct to Entity::Project
  2. clone_repo - clone if not exists locally (15-50% progress)
  3. appraise_contributions - run git blame analysis (55-85% progress)
  4. cache_result - store JSON in Redis with TTL (90-100% progress)
  ↓
Faye notification: 100% progress
  ↓
Client retries → API returns cached result
```

**Getting project list:**
```
GET /api/v1/projects?list={base64_json_array}
  ↓
Controller → Request::EncodedProjectList.new(params)
  ↓
Controller → Service::ListProjects.call(list_request: list_req)
  ↓
Service steps:
  1. validate_list (check list parameter exists)
  2. retrieve_list
     - Decode base64 JSON list
     - Repository::For.klass(Entity::Project).find_full_name for each
     - Filter out nil results
     - Create Response::ProjectsList
  ↓
Controller receives Success(ApiResult) or Failure(ApiResult)
  ↓
Representer::HttpResponse wraps result
  ↓
Representer::ProjectsList.new(projects).to_json
  ↓
JSON response with 200 status
```

## Database Schema

**Tables:**
- `members`: GitHub users (origin_id, username, email)
- `projects`: GitHub repos (origin_id, name, size, urls, owner_id FK)
- `projects_members`: Join table for many-to-many contributors relationship

**Migrations:** `db/migrations/00X_*.rb`

## Configuration

**Environment Management:**
- Uses **Figaro** for configuration (`config/secrets.yml`)
- Separate databases per environment (controlled by `RACK_ENV`)
- `require_app.rb`: Smart loader for selective layer loading
  - Default loads: `domain`, `infrastructure`, `application`, `presentation`
  - Can selectively load layers: `require_app(%w[domain infrastructure])`
  - Enables loading subsets for console/testing

**Key Config Files:**

- `config/environment.rb`: Loads Figaro, sets up Sequel database
- `config/secrets.yml`: GitHub token, database filename, Redis URL (git-ignored)
- `config.ru`: Rack application entry point with Faye websocket support
- `require_app.rb`: Layer-selective code loader for API
- `require_worker.rb`: Layer-selective code loader for worker

**Caching Configuration:**

- **Development**: Redis database 0 (`redis://localhost:6379/0`)
- **Test**: Redis database 1 (`redis://localhost:6379/1`)
- **Production**: Redis cloud cache at `REDIS_URL`

## Testing Strategy

**Test Organization:**
Tests are organized by scope in `spec/tests/`:
- `unit/`: Unit tests for individual classes (mappers, value objects, entities)
- `integration/`: Integration tests (database + gateways, cross-layer interactions)
- `acceptance/`: End-to-end API tests through HTTP interface (using Rack::Test)

**Test Helpers (`spec/helpers/`):**
- `spec_helper.rb`: Shared test configuration
- `vcr_helper.rb`: VCR configuration for HTTP recording
- `database_helper.rb`: Database cleanup utilities

**API Testing (Acceptance):**
- Uses **Rack::Test** to make HTTP requests to the API
- Tests JSON responses and HTTP status codes
- Example: `get "/api/v1/projects/#{owner}/#{name}"` then parse JSON
- All acceptance tests verify JSON structure and content

**VCR (HTTP Recording):**
- Records GitHub API responses to `spec/fixtures/cassettes/*.yml`
- Enables offline testing without real API calls
- Filters sensitive tokens from cassettes
- Use `rake vcr:wipe` to delete and re-record

**Database Testing:**
- `DatabaseHelper.wipe_database` clears all tables between tests
- Separate test database (`RACK_ENV=test`)

**Test Fixtures:**
- `spec/fixtures/cassettes/`: VCR HTTP response recordings
- `spec/fixtures/project_info.rb`: Sample project data for tests
- `spec/fixtures/github_results.yml`: Expected GitHub API response structures

## Working in This Codebase

**Code Location Decisions:**

*API (`app/`):*
- Domain entities & value objects → `app/domain/{context}/entities/` or `app/domain/{context}/values/`
- Domain logic & calculations → `app/domain/{context}/lib/`
- Data transformation → `app/infrastructure/*/mappers/`
- External service access → `app/infrastructure/*/gateway/` or `app/infrastructure/*/gateways/`
- Database CRUD operations → `app/infrastructure/database/repositories/`
- Database schema → `app/infrastructure/database/orm/`
- Caching → `app/infrastructure/cache/`
- HTTP routes → `app/application/controllers/app.rb`
- Service objects (business workflows) → `app/application/services/`
- Request parsing → `app/application/requests/`
- Response data structures → `app/application/responses/` and `app/presentation/responses/`
- JSON representers → `app/presentation/representers/`

*Worker (`workers/`):*

- Contributions domain (git analysis) → `workers/domain/contributions/`
- Git operations → `workers/infrastructure/git/`
- Faye messaging → `workers/infrastructure/messaging/`
- Progress tracking → `workers/presentation/values/`
- Worker entry point → `workers/application/controllers/worker.rb`
- Worker services → `workers/application/services/`
- Request handling → `workers/application/requests/`

**Adding a New API Endpoint:**
1. Define service object in `app/application/services/` using Dry::Transaction
2. Create request object in `app/application/requests/` if needed
3. Create response struct in `app/application/responses/` or `app/presentation/responses/`
4. Add route in `app/application/controllers/app.rb`
5. Create representer in `app/presentation/representers/` for JSON serialization
6. Write acceptance test in `spec/tests/acceptance/api_spec.rb`
7. Add integration tests for service in `spec/tests/integration/`

**Adding a New Domain Feature:**
1. Create/modify domain entities in `app/domain/{context}/entities/`
2. Create/modify value objects in `app/domain/{context}/values/`
3. Add domain logic/calculations in `app/domain/{context}/lib/`
4. Add database migration if schema changes (`db/migrations/`)
5. Create/update ORM model in `app/infrastructure/database/orm/`
6. Add repository methods in `app/infrastructure/database/repositories/`
7. Create mappers in `app/infrastructure/*/mappers/` to transform external data
8. Create service object in `app/application/services/`
9. Create representer in `app/presentation/representers/`
10. Write tests in `spec/tests/{unit,integration,acceptance}/`

**Dependency Injection Pattern:**
- Infrastructure classes accept gateway/config parameters for testability
- Example: `ProjectMapper.new(github_token)` or `ProjectMapper.new(gateway_instance)`

**Type Safety:**
- Use `Dry::Types` for entity attributes: `Strict::String`, `Strict::Integer`, etc.
- `Integer.optional` for nullable fields (e.g., database IDs)
- Entities validate types on instantiation

## Technology Stack

- **Web**: Roda 3.x (routing), Puma 6.x (server)
- **JSON Serialization**: Roar (Representers with hypermedia)
- **Data**: Dry-Struct/Dry-Types (validation), Dry-Transaction (services), Sequel 5.x (ORM), SQLite (dev/test), PostgreSQL (production)
- **Caching**: Redis (primary cache for appraisals)
- **Background Jobs**: Shoryuken 6.x (worker), AWS SQS (queue)
- **Websockets**: Faye (real-time progress updates)
- **HTTP**: HTTP gem 5.x
- **Testing**: Minitest, Rack::Test, VCR, WebMock, SimpleCov
- **Quality**: RuboCop, Reek, Flog

## Important Notes

- **This is a Web API only** - there is no web interface
- All responses are JSON (via Roar representers)
- Hypermedia links are embedded in JSON responses (HATEOAS)
- Redis is the primary cache for appraisal results (no Rack::Cache)
- Services use Dry::Transaction for railway-oriented programming
- Controllers should be thin - delegate to services
- Representers handle JSON serialization - domain entities stay pure
- Background worker handles async git clone and appraisal operations via AWS SQS
- Real-time progress updates sent to clients via Faye websockets

## Heroku Deployment

**Procfile Processes:**

- `release`: Runs `rake db:migrate` and `rake queues:create` on each deploy
- `web`: Puma web server with Faye websocket support
- `worker`: Shoryuken background worker for git clone and appraisal jobs

**Required Heroku Config Vars:**

- `GITHUB_TOKEN`: GitHub API access token
- `AWS_ACCESS_KEY_ID`: AWS credentials for SQS
- `AWS_SECRET_ACCESS_KEY`: AWS credentials for SQS
- `AWS_REGION`: AWS region (e.g., `us-east-1`)
- `WORKER_QUEUE`: SQS queue name
- `WORKER_QUEUE_URL`: Full SQS queue URL
- `API_HOST`: API base URL (e.g., `https://your-app.herokuapp.com`)
- `REDIS_URL`: Redis URL for caching (provision your own Redis instance)
- `DATABASE_URL`: PostgreSQL URL (auto-set by Heroku Postgres add-on)

**Scaling:**

```bash
heroku ps:scale web=1 worker=1
```

**Architecture Note:** Web and worker dynos run in separate isolated containers with ephemeral filesystems. The worker clones repos to its local ephemeral storage, performs git blame analysis, and caches the serialized JSON results in Redis. The API then retrieves cached results from Redis - it never accesses the cloned repos directly. This architecture works both locally and in production Heroku deployments.
