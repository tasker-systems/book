# Technical Context: GitBook & Tasker Integration

## Technology Stack

### GitBook Platform
- **GitBook CLI**: Local development and building
- **GitBook.com**: Hosted publishing platform
- **Node.js**: Runtime for GitBook tooling
- **Markdown**: Primary content format
- **JSON**: Configuration and metadata

### Tasker Engine Integration
- **Ruby 3.0+**: Required for Tasker examples
- **Rails 7.0+**: Web framework for Tasker
- **PostgreSQL**: Database for Tasker's SQL functions
- **Redis**: Background job processing
- **Sidekiq**: Job queue system

### Development Tools
- **Git**: Version control
- **Cursor**: AI-powered development environment
- **Ruby LSP**: Language server for Ruby development
- **Bash**: Setup and automation scripts

## Development Setup

### Local GitBook Environment
```bash
# Install GitBook CLI
npm install -g gitbook-cli

# Install project dependencies
npm install

# Install GitBook plugins
gitbook install

# Serve locally
gitbook serve
# Visit http://localhost:4000

# Build for production
gitbook build
# Output in _book/ directory
```

### Tasker Example Environment
```bash
# Prerequisites
ruby -v    # 3.0+
rails -v   # 7.0+
psql --version
redis-server --version

# Tasker installation
gem install tasker
# Or in Gemfile: gem 'tasker', '~> 2.5.0'
```

### Project Structure Integration
```
tasker-blog/
├── book.json                    # GitBook configuration
├── package.json                 # Node.js dependencies
├── styles/website.css           # Custom GitBook styling
├── blog/posts/*/setup-scripts/  # Tasker installation automation
├── blog/posts/*/code-examples/  # Working Tasker implementations
└── docs/                        # Tasker reference documentation
```

## Technical Constraints

### GitBook Limitations
- **Plugin Dependencies**: Must use compatible GitBook plugin versions
- **Build Performance**: Large repositories can have slow build times
- **File Size Limits**: Individual files should be under 1MB
- **Navigation Depth**: Limited nesting levels in SUMMARY.md

### Tasker Requirements
- **Database**: PostgreSQL required for SQL functions
- **Ruby Version**: Minimum Ruby 3.0 for modern syntax
- **Rails Version**: Rails 7.0+ for current ActiveRecord features
- **Background Jobs**: Redis/Sidekiq required for async processing

### Repository Exclusions
- **Development Files**: `.cursor/`, `memory-bank/`, `.ruby-lsp/`
- **Build Artifacts**: `_book/`, `node_modules/`, `.gitbook/`
- **Sensitive Data**: API keys, database credentials

## Configuration Management

### GitBook Configuration (book.json)
```json
{
  "root": ".",
  "title": "Tasker: Real-World Engineering Stories",
  "plugins": [
    "github", "edit-link", "copy-code-button",
    "prism", "anchorjs", "ga", "sitemap-general"
  ],
  "variables": {
    "version": "2.5.0",
    "github_repo": "jcoletaylor/tasker",
    "install_url": "https://raw.githubusercontent.com/jcoletaylor/tasker/main/scripts/install-tasker-app.sh"
  }
}
```

### Plugin Configuration
- **GitHub Integration**: Links to source repository
- **Edit Links**: Community contribution workflow
- **Syntax Highlighting**: Ruby, Bash, YAML, JSON support
- **Analytics**: Google Analytics integration
- **SEO**: Sitemap generation for search engines

### Custom Styling (styles/website.css)
- **Code Block Themes**: Dark theme for better readability
- **Responsive Design**: Mobile-optimized layouts
- **Print Styles**: PDF export optimization
- **Accessibility**: WCAG compliance considerations

## Development Workflow

### Content Development Process
1. **Local Development**: Use `gitbook serve` for live preview
2. **Code Testing**: Validate all Tasker examples work
3. **Setup Automation**: Test one-command installation scripts
4. **GitBook Build**: Verify clean build without errors
5. **Repository Commit**: Push changes to trigger publication

### Code Example Validation
```bash
# Test chapter setup script
cd blog/posts/post-01-ecommerce-reliability/setup-scripts/
./setup.sh

# Verify Tasker functionality
cd ecommerce-blog-demo
bundle exec rails tasker:status
bundle exec rails tasker:test_workflow ecommerce process_order
```

### Quality Assurance
- **Link Validation**: All internal and external links work
- **Code Execution**: All examples run successfully
- **Cross-Platform**: Scripts work on macOS, Linux, Windows (WSL)
- **Error Handling**: Graceful failure with helpful error messages

## Deployment Architecture

### GitBook.com Integration
- **GitHub Connection**: Automatic builds on repository pushes
- **Branch Strategy**: Main branch triggers production deployment
- **Build Triggers**: Changes to content files trigger rebuilds
- **Domain Configuration**: Custom domain setup if needed

### Content Delivery
- **CDN**: GitBook.com provides global content delivery
- **SSL**: HTTPS enabled by default
- **Caching**: Automatic caching for performance
- **Analytics**: Built-in traffic and engagement metrics

### Backup Strategy
- **Git Repository**: Primary backup through version control
- **GitBook Export**: Periodic PDF/HTML exports
- **Code Examples**: Separate repository for Tasker examples
- **Documentation**: Comprehensive setup instructions

## Performance Considerations

### GitBook Optimization
- **Image Compression**: Optimize images for web delivery
- **File Organization**: Logical directory structure
- **Plugin Selection**: Only essential plugins to minimize build time
- **Content Chunking**: Break large files into manageable sections

### Tasker Example Performance
- **Database Optimization**: Proper indexing for example data
- **Background Processing**: Efficient job queue configuration
- **Resource Management**: Appropriate memory and CPU limits
- **Monitoring**: Built-in health checks and metrics

## Security Considerations

### Repository Security
- **Sensitive Data**: No credentials or API keys in repository
- **Access Control**: Proper GitHub repository permissions
- **Dependency Management**: Regular security updates for npm packages
- **Content Review**: All community contributions reviewed

### Tasker Example Security
- **Database Security**: Secure connection strings and credentials
- **API Security**: Proper authentication for external services
- **Input Validation**: Secure handling of user inputs
- **Production Readiness**: Security patterns for enterprise deployment

## Monitoring and Maintenance

### GitBook Health
- **Build Status**: Monitor successful builds and deployments
- **Link Checking**: Regular validation of all links
- **Performance**: Page load times and user experience
- **Analytics**: Reader engagement and popular content

### Tasker Example Maintenance
- **Version Compatibility**: Keep examples current with Tasker releases
- **Dependency Updates**: Regular gem and package updates
- **Testing**: Continuous validation of all code examples
- **Community Feedback**: Responsive to user issues and suggestions
