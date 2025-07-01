# GitBook Setup Guide

This guide explains how to work with the GitBook structure and publish your Tasker engineering stories.

## 📚 GitBook Structure Overview

Your repository is now optimized for GitBook with the following structure:

```
tasker-blog/
├── README.md                    # Main landing page
├── SUMMARY.md                   # Table of contents (GitBook navigation)
├── getting-started.md           # Getting started guide
├── book.json                    # GitBook configuration
├── package.json                 # Node.js dependencies for GitBook
├── styles/                      # Custom CSS styling
│   └── website.css             # Custom GitBook styles
├── blog/posts/                  # All blog content
│   ├── post-01-ecommerce-reliability/  # ✅ Complete chapter
│   ├── post-02-data-pipeline-resilience/  # 🔄 Preview only
│   └── [other chapters...]     # 🔄 Preview only
└── appendices/                  # Reference materials
    ├── code-repository.md       # Complete code reference
    ├── troubleshooting.md       # Setup troubleshooting
    ├── tasker-docs.md          # Tasker documentation links
    └── contributing.md         # Contribution guidelines
```

## 🚀 Quick Start

### Local Development

1. **Install GitBook CLI**:
```bash
npm install -g gitbook-cli
```

2. **Install dependencies**:
```bash
cd /Users/petetaylor/projects/tasker-blog
npm install
gitbook install
```

3. **Serve locally**:
```bash
gitbook serve
# Visit http://localhost:4000
```

4. **Build for production**:
```bash
gitbook build
# Output in _book/ directory
```

### GitBook.com Integration

1. **Connect your GitHub repository** to GitBook.com
2. **Set the root directory** to `/Users/petetaylor/projects/tasker-blog`
3. **GitBook will automatically detect** the `book.json` configuration
4. **Publishing is automatic** on Git pushes to main branch

## 🎯 Key GitBook Features Configured

### ✅ **Plugins Enabled**
- **`github`**: Links to your GitHub repository
- **`edit-link`**: "Edit this page" links for contributors
- **`copy-code-button`**: One-click code copying
- **`prism`**: Enhanced syntax highlighting for Ruby, Bash, YAML
- **`anchorjs`**: Automatic anchor links for headings

### 🎨 **Custom Styling**
- **Code blocks**: Dark theme with syntax highlighting
- **Callout boxes**: Blue-themed blockquotes for tips
- **Tables**: Clean styling for comparison tables
- **Mobile responsive**: Optimized for all devices

### 📊 **Analytics Ready**
- **Google Analytics**: Update `GA-XXXXXXXX-X` in `book.json`
- **Sitemap**: Automatically generated for SEO

## 📝 Content Guidelines

### Writing for GitBook

**Markdown Features**:
```markdown
# Chapter Title

> **Tip**: Use blockquotes for important callouts

## Section Headers
Use `##` for main sections within chapters

### Subsections
Use `###` for subsections

**Code Blocks**:
```ruby
# Ruby code with syntax highlighting
class TaskHandler < Tasker::TaskHandler::Base
end
```

**Tables**:
| Feature | Before | After |
|---------|--------|--------|
| Reliability | 85% | 99.8% |

**Task Lists**:
- [ ] Incomplete task
- [x] Completed task
```

### Chapter Structure

Each chapter should follow this pattern:

```markdown
# Chapter X: Title

> **Story Hook**: Compelling one-liner about the engineering problem

## 🎯 What You'll Learn
- Key concepts
- Practical skills
- Business outcomes

## 🚀 Try It Now
```bash
# One-line setup command
curl -fsSL .../setup.sh | bash
```

## The Story
[Full narrative content]

## Key Takeaways
[Actionable insights]

## What's Next
[Links to related chapters]
```

## 🔧 Development Workflow

### Adding New Content

1. **Create content files** in appropriate directories
2. **Update SUMMARY.md** to include new pages in navigation
3. **Test locally** with `gitbook serve`
4. **Commit and push** to trigger automatic deployment

### Working with Code Examples

**File Organization**:
- Keep code in `blog/posts/[chapter]/code-examples/`
- Link to code from markdown with relative paths
- Test all code examples before publishing

**Linking to Code**:
```markdown
See the complete implementation in [code-examples/task_handler/order_processing_handler.rb](code-examples/task_handler/order_processing_handler.rb).
```

### Managing Chapter Previews

**For unreleased chapters**:
- Create basic README.md with "Coming Soon" content
- Add preview.md with story teaser
- Update SUMMARY.md to link to preview pages
- Include target release dates

## 🎨 Customization Options

### Styling Changes

Edit `styles/website.css` to customize:
- Color schemes
- Typography
- Code block styling
- Table formatting
- Mobile responsiveness

### Plugin Configuration

Modify `book.json` to:
- Add/remove GitBook plugins
- Configure analytics
- Update repository links
- Customize export settings

### Variables and Templating

Use variables in `book.json` for:
```json
{
  "variables": {
    "version": "1.0.0",
    "github_repo": "tasker-systems/tasker",
    "install_url": "https://raw.githubusercontent.com/..."
  }
}
```

Reference in markdown:
```markdown
Current Tasker version: {{ book.version }}
```

## 📊 Analytics and SEO

### GitBook.com Benefits
- **Automatic SEO optimization**
- **Built-in analytics dashboard**
- **Social media integration**
- **PDF/ePub export**
- **Full-text search**

### Custom Analytics

Update `book.json` with your tracking IDs:
```json
{
  "pluginsConfig": {
    "ga": {
      "token": "UA-XXXXXXXX-X"
    }
  }
}
```

## 🚀 Publishing Strategy

### Content Release Schedule

**Phase 1 (Immediate)**:
- [x] Chapter 1: E-commerce Reliability (Complete)
- [x] GitBook structure and navigation
- [x] Appendices and reference materials

**Phase 2 (Q1 2024)**:
- [ ] Chapter 2: Data Pipeline Resilience
- [ ] Enhanced code examples
- [ ] Video content integration

**Phase 3 (Q2-Q4 2024)**:
- [ ] Remaining chapters (3-6)
- [ ] Interactive examples
- [ ] Community contributions

### Promotion Channels

**Primary**:
- GitBook.com hosted site
- GitHub repository
- Engineering blogs and newsletters

**Secondary**:
- Social media (Twitter, LinkedIn)
- Conference presentations
- Podcast appearances

## 🤝 Collaboration

### For Contributors

**Content Guidelines**:
- Follow established chapter structure
- Test all code examples
- Update navigation in SUMMARY.md
- Use consistent writing style

**Review Process**:
- Create pull requests for changes
- Test GitBook build locally
- Ensure mobile responsiveness
- Verify all links work

### For Maintainers

**Regular Tasks**:
- Review and merge contributions
- Update target release dates
- Monitor analytics and engagement
- Maintain code example compatibility

## 📞 Support

### GitBook Issues
- **Local build problems**: Check Node.js and GitBook CLI versions
- **Plugin errors**: Verify plugin compatibility in `book.json`
- **Styling issues**: Test CSS changes in `styles/website.css`

### Content Issues
- **Broken links**: Use relative paths for internal content
- **Code examples**: Test in clean environment before publishing
- **Navigation**: Ensure SUMMARY.md matches directory structure

---

**🎉 Your GitBook is ready!**

Start with `gitbook serve` to see your engineering stories come to life, then push to GitBook.com for automatic publishing.

*Transform complex engineering stories into engaging, interactive documentation that helps developers worldwide.*
