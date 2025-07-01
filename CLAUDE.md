# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitBook documentation project that presents the Tasker Rails workflow orchestration engine through narrative-driven engineering stories. The project combines technical documentation with compelling storytelling to teach workflow orchestration concepts.

## Development Commands

### Core GitBook Operations
```bash
npm run serve    # Serve locally for development (http://localhost:4000)
npm run build    # Build static site for production
npm run install  # Install GitBook plugins (run after modifying book.json)
```

### Tasker Repository Integration
```bash
# Tasker engine repository location
cd /Users/petetaylor/projects/tasker

# Check current Tasker version
grep version lib/tasker/version.rb

# Review recent changes in Tasker docs
ls -la docs/*.md | head -10
```

### Testing and Validation
```bash
# Always test local build before committing
npm run serve

# Validate all chapter examples work
cd blog/posts/[chapter-name]/setup-scripts && bash setup.sh

# Test specific chapter
cd blog/posts/post-01-ecommerce-reliability && bash setup-scripts/setup.sh
```

## Architecture and Structure

### Content Organization
- **`blog/posts/`** - Main chapter content with strict structure:
  - `README.md` - Chapter overview and navigation
  - `blog-post.md` - Main narrative content
  - `code-examples/` - Complete working code demonstrations
  - `setup-scripts/` - One-command installation scripts
  - `TESTING.md` - Troubleshooting and testing guide
  - `preview.md` - Teaser for unreleased chapters

- **`docs/`** - Technical reference documentation
- **`appendices/`** - Supporting materials and troubleshooting
- **`memory-bank/`** - Development context (NEVER publish)
- **`.cursor/`** - Development environment config (NEVER publish)

### Chapter Development Standards
Each chapter must include:
1. **Runnable Code**: All examples execute with single command
2. **Cross-Platform**: Scripts work on macOS, Linux, Windows (WSL)
3. **Production Quality**: Proper error handling and monitoring
4. **Narrative Continuity**: Characters and company evolve across chapters

## GitBook Configuration

### Critical Files
- **`book.json`** - GitBook configuration, plugins, and build settings
- **`SUMMARY.md`** - Table of contents and navigation structure
- **`package.json`** - Node.js dependencies and scripts
- **`.bookignore`** - Files excluded from GitBook build

### Repository Exclusion Strategy
**CRITICAL**: Development files must NEVER be published to GitBook:
- Multiple redundant exclusion methods in place
- `.cursor/`, `memory-bank/`, `.ruby-lsp/` are excluded via book.json and GitBook settings
- Always verify exclusions work with local build testing
- Use SUMMARY.md to control what gets published

## Current Development Status (2025-07-01)

### Recently Completed ✅
- **Chapter 1**: Updated all API field names to match Tasker v2.7.0 (`step.results`, `task.status`, `sequence.steps`)
- **Chapter 2**: Fixed SQL function references and validated workflow steps vs event subscribers pattern
- **Chapter 3**: Complete microservices coordination implementation with Faraday-based API handlers
- **API Base Handler**: Enhanced base class that properly extends Tasker::StepHandler::Api
- **Step Handlers**: All 5 handlers use Tasker's native circuit breaker architecture
- **Field Name Audit**: Fixed all timeout/retry field placement across all chapters
- **Circuit Breaker Revelation**: Replaced custom circuit breaker with Tasker's superior SQL-driven approach
- **Documentation Sync**: Updated to Tasker v2.7.0 with advanced analytics capabilities

### Next Priority Tasks 🎯
1. **Chapter 3 Setup Scripts**: Docker multi-service demo with 4 services (user, billing, preferences, notification)
2. **Docker Compose**: Configuration for Chapter 3 local development environment
3. **Chapter 3 Narrative**: Update blog-post.md to maintain story continuity with Sarah's team

### Key Technical Achievements 🚀
- **Enhanced ApiBaseHandler**: Leverages Tasker's native circuit breaker architecture via typed errors
- **Microservices Pattern**: Single Tasker coordinating multiple HTTP services with SQL-driven resilience
- **Architecture Insight**: Discovered Tasker's distributed circuit breaker > in-memory implementations
- **Error Classification**: `RetryableError` vs `PermanentError` for intelligent retry logic
- **Distributed Tracing**: Correlation IDs across all service boundaries
- **Production Patterns**: Idempotency, persistent circuit state, and dependency-aware recovery

### Files Ready for Integration into Tasker Engine 💎
- `api_base_handler.rb` - Enhanced base class demonstrating proper Tasker::StepHandler::Api extension
- `CIRCUIT_BREAKER_EXPLANATION.md` - Documents why Tasker's approach is superior to custom implementations
- All step handlers demonstrate proper Faraday usage with typed error handling
- Examples show how `RetryableError` vs `PermanentError` creates intelligent circuit breaker behavior

## Content Development Workflow

### Character Continuity
- **Characters**: Sarah's engineering team evolves across all chapters
- **Company**: GrowthCorp (e-commerce) with growing technical complexity
- **Technical Progression**: Each chapter builds on previous implementation patterns

### Code Quality Requirements
- All Tasker examples must use version 2.7.0 consistently (production-ready)
- Ruby 3.2+, Rails 7.2+, PostgreSQL, Redis dependencies
- Thread-safe registry systems with structured logging
- Enterprise-ready patterns: namespace organization, semantic versioning
- Background job processing with Sidekiq
- Built-in observability: OpenTelemetry integration, event system (56 events)
- REST API and GraphQL capabilities with health monitoring
- Production validation: 1,692 passing tests

### Chapter Development Priority
1. **Chapter 2**: Data Pipeline Resilience (immediate focus)
2. **Chapters 3-6**: Sequential development with community feedback
3. Code examples must work before narrative completion

## Operational Patterns

### Before Making Changes
- Always run `npm run serve` to test local build
- Verify all setup scripts execute successfully
- Check that navigation in SUMMARY.md is correct
- Ensure development files remain excluded from build

### When Adding New Chapters
- Follow strict directory structure pattern
- Include all required files (README, blog-post, code-examples, setup-scripts, TESTING)
- Add to SUMMARY.md navigation
- Test all code examples work immediately
- Maintain character and story continuity

### When Modifying GitBook Configuration
- Test locally before committing changes
- Verify plugin compatibility
- Check that build performance remains acceptable
- Validate that exclusions still work properly

## Technology Stack Context

- **Primary Platform**: GitBook for documentation generation
- **Code Examples**: Ruby/Rails with Tasker workflow orchestration engine
- **Dependencies**: PostgreSQL, Redis, Sidekiq for background processing
- **Monitoring**: OpenTelemetry integration in examples
- **Development**: Node.js/npm for GitBook CLI tooling

## Current Development Status

### Completed Work
- **Chapter 1**: E-commerce Reliability (complete with Tasker v2.6.0 patterns)
- **Documentation Integration**: Comprehensive Tasker documentation integrated
- **Repository Integration**: Clear links to main Tasker repository established
- **GitBook Infrastructure**: Complete setup with plugins and custom styling

### Active Priority
- **Chapter 2**: Data Pipeline Resilience (in development with enterprise patterns)
- All examples use current Tasker architecture (namespace organization, thread-safe operations)
- Integration with DummyJSON API for realistic scenarios

### Planned Chapters
- **Chapter 3**: Microservices Coordination
- **Chapter 4**: Team Scaling and Namespace Organization  
- **Chapter 5**: Production Observability
- **Chapter 6**: Enterprise Security

## Version Update Workflow

When Tasker releases a new version:

### 1. Immediate Assessment
```bash
# Check version in Tasker repository
cd /Users/petetaylor/projects/tasker
grep version lib/tasker/version.rb

# Review README.md for version requirements
head -50 README.md | grep -E "Ruby|Rails|PostgreSQL"

# Check key documentation for new features
ls -la docs/*.md | head -10
```

### 2. Documentation Review
Focus on these files for version-specific changes:
- **README.md** - System requirements, installation commands
- **docs/OVERVIEW.md** - Architectural changes
- **docs/DEVELOPER_GUIDE.md** - API or pattern updates  
- **docs/QUICK_START.md** - Setup procedure changes
- **docs/APPLICATION_GENERATOR.md** - New generator features

### 3. GitBook Update Process
```bash
# Update version references in GitBook
grep -r "2\.6\.2" . --include="*.md" --include="*.json"

# Update system requirements in documentation
grep -r "Ruby 3\.0" . --include="*.md"
grep -r "Rails 7\.0" . --include="*.md"

# Test local build after updates
npm run serve
```

### 4. Key Areas to Update
- Version numbers in all examples and setup scripts
- System requirements (Ruby, Rails versions)
- Installation commands and procedures
- New features or capabilities in chapter examples
- Breaking changes or deprecations

## Common Troubleshooting

- **Build fails**: Check `book.json` syntax and plugin compatibility
- **Development files exposed**: Verify exclusion settings in multiple locations
- **Code examples broken**: Test with fresh environment using setup scripts
- **Navigation issues**: Check SUMMARY.md structure and file paths
- **Slow builds**: Review file sizes and consider splitting large chapters
- **Tasker examples**: Use automated demo builder approach from main repository
- **Version mismatches**: Ensure all references use current Tasker version consistently