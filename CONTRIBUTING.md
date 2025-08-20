# Contributing to RiceBarMac

Thank you for your interest in contributing to RiceBarMac! This document provides guidelines and information for contributors.

## 🚀 Getting Started

### Development Setup

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/MateoCerquetella/RiceBarMac.git
   cd RiceBarMac
   ```
3. **Install dependencies**:
   ```bash
   brew install xcodegen
   xcodegen generate
   ```
4. **Open in Xcode**:
   ```bash
   open RiceBarMac.xcodeproj
   ```

### Prerequisites

- macOS Sonoma (14+) or later
- Xcode 15+
- Basic knowledge of Swift and SwiftUI
- Familiarity with macOS development

## 📝 Code Guidelines

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftUI for UI components when possible
- Maintain compatibility with macOS 14+
- Use meaningful variable and function names
- Add documentation for public APIs

### Code Organization

- **Services**: Business logic and data management
- **ViewModels**: UI state management (MVVM pattern)
- **Views**: SwiftUI and AppKit UI components
- **Utils**: Helper functions and extensions
- **Models**: Data structures and types

### Testing

- Write unit tests for new functionality
- Test on multiple macOS versions when possible
- Verify backwards compatibility
- Test with different profile configurations

## 🐛 Bug Reports

When reporting bugs, please include:

- **macOS version and hardware**
- **Steps to reproduce** the issue
- **Expected vs actual behavior**
- **Screenshots or logs** if helpful
- **Profile configuration** if relevant

Use the bug report template when creating issues.

## ✨ Feature Requests

Before suggesting new features:

1. **Check existing issues** for similar requests
2. **Consider the scope** - does it fit RiceBarMac's purpose?
3. **Provide use cases** and examples
4. **Consider implementation complexity**

Use the feature request template when creating issues.

## 🔄 Pull Request Process

### Before Submitting

1. **Create an issue** first to discuss major changes
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
3. **Make your changes** following the code guidelines
4. **Test thoroughly** on your local setup
5. **Update documentation** if needed

### PR Requirements

- [ ] Code follows project style guidelines
- [ ] Tests pass (if applicable)
- [ ] Documentation updated (if needed)
- [ ] PR description explains the changes
- [ ] Linked to relevant issue(s)

### PR Review Process

1. **Automated checks** must pass
2. **Code review** by maintainers
3. **Testing** on different configurations
4. **Approval** and merge by maintainers

## 🎯 Areas for Contribution

### High Priority
- **Performance optimizations**
- **Bug fixes and stability**
- **Test coverage improvements**
- **Documentation enhancements**

### Medium Priority
- **New profile features**
- **Additional terminal support**
- **UI/UX improvements**
- **Accessibility enhancements**

### Low Priority
- **Code refactoring**
- **Developer tooling**
- **Example configurations**

## 📋 Issue Templates

### Bug Report
```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- macOS version: [e.g. 14.1]
- RiceBarMac version: [e.g. 1.0.0]
- Hardware: [e.g. M1 MacBook Pro]

**Additional context**
Any other context about the problem.
```

### Feature Request
```markdown
**Is your feature request related to a problem?**
A clear description of what the problem is.

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Any alternative solutions or features you've considered.

**Additional context**
Any other context or screenshots about the feature request.
```

## 🔧 Development Tips

### Debugging
- Use Xcode's debugger and console
- Check Console.app for system logs
- Test with different profile configurations
- Use Activity Monitor for performance issues

### Testing Profiles
Create test profiles in `~/.ricebar/profiles/` for development:
```bash
mkdir -p ~/.ricebar/profiles/TestProfile/home/.config
echo "Test content" > ~/.ricebar/profiles/TestProfile/home/.config/test.txt
```

### Common Issues
- **Permissions**: Ensure proper entitlements are set
- **Sandboxing**: Release builds have different permissions
- **File Watching**: FSEvents may need debugging
- **UI Updates**: SwiftUI state management quirks

## 📞 Getting Help

- **GitHub Discussions**: For questions and ideas
- **Issues**: For bugs and feature requests
- **Code Review**: Request feedback on drafts

## 🎉 Recognition

Contributors will be:
- **Listed in CONTRIBUTORS.md**
- **Mentioned in release notes**
- **Credited in the app's About section**

Thank you for contributing to RiceBarMac! 🍚