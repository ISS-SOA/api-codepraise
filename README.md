# CodePraise Web API

Web API that allows Github *projects* to be *appraised* for individual *contributions* by *members* of a team.

## Setup

### Prerequisites

1. **Ruby** - See `.ruby-version` for required version
2. **Redis** - Required for caching appraisal results
3. **AWS Account** - For SQS message queue (worker communication)

### Install Redis

**Using rake tasks (recommended):**

```bash
rake redis:start    # Start Redis Docker container
rake redis:stop     # Stop Redis when done
rake redis:status   # Check connectivity
```

**Or manually with Homebrew (macOS):**

```bash
brew install redis
brew services start redis
```

### Install Dependencies

```bash
bundle install
```

### Configure Secrets

```bash
cp config/secrets_example.yml config/secrets.yml
```

Edit `config/secrets.yml` and add your:

- `GITHUB_TOKEN` - GitHub personal access token
- AWS credentials for SQS queue

### Setup Database

```bash
bundle exec rake db:migrate                  # Development database
RACK_ENV=test bundle exec rake db:migrate    # Test database
```

### Verify Setup

```bash
rake redis:status    # Check Redis connectivity
rake queues:status   # Check SQS queue status
```

## Running the Application

```bash
rake run             # Start API server on port 9090
rake worker:run:dev  # Start background worker (in separate terminal)
```

## Testing

```bash
rake spec            # Run unit and integration tests
bash spec/acceptance_tests   # Run full acceptance tests (starts worker automatically)
```

## Routes

### Root check

`GET /`

Status:

- 200: API server running (happy)

### Appraise a previously stored project

`GET /projects/{owner_name}/{project_name}[/{folder}/]`

Status

- 200: appraisal returned (happy)
- 404: project or folder not found (sad)
- 500: problems finding or cloning Github project (bad)

### Store a project for appraisal

`POST /projects/{owner_name}/{project_name}`

Status

- 201: project stored (happy)
- 404: project or folder not found on Github (sad)
- 500: problems storing the project (bad)
