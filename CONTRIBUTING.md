# Contributing to EXdl

Thank you for your interest in contributing to **EXdl**! Whether you are reporting a bug, proposing a new feature, or submitting code, your contributions are welcome.

---

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please report any unacceptable behavior to [erdembeler@hotmail.com](mailto:erdembeler@hotmail.com).

---

## How Can I Contribute?

### 1. Reporting Bugs

Before creating a bug report, please check existing issues to ensure it has not already been reported.

When reporting a bug via [GitHub Issues](https://github.com/erdembeler/exdl/issues/new?template=bug_report.md), please include:
- **macOS version** (e.g., macOS 15.0 Sequoia, macOS 14.5 Sonoma)
- **EXdl version** (e.g., v1.0.0)
- **External drive format** (e.g., APFS, Mac OS Extended)
- **Steps to reproduce** the problem
- **Expected vs. actual behavior**
- Any relevant logs or screenshots (avoid sharing sensitive data)

### 2. Suggesting Enhancements

Feature requests are tracked as GitHub Issues. When opening a feature request:
- Explain the practical use case and problem it solves.
- Describe your proposed solution or user experience.
- Keep in mind EXdl's design philosophy: native, lightweight, privacy-focused, and seamlessly aligned with Apple macOS guidelines.

### 3. Submitting Pull Requests

1. **Fork the repository** and clone your fork locally.
2. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```
3. **Make your changes**:
   - Write clean, idiomatic Swift.
   - Maintain backward compatibility where applicable.
   - Respect macOS Human Interface Guidelines (avoid non-standard UI patterns).
4. **Build and test locally**:
   ```bash
   # Test building with Swift Package Manager:
   swift build -c release

   # Build the application bundle:
   ./build_app.sh
   ```
5. **Commit your changes**:
   - Use clear, descriptive English commit messages following conventional commit guidelines (e.g., `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`).
6. **Push to your fork and submit a Pull Request** targeting the `main` branch.

---

## Development Setup

- **Operating System:** macOS 14.0 (Sonoma) or later
- **Toolchain:** Xcode 15.0+ or Swift 5.10+
- **Architecture:** Universal Apple Silicon (`arm64`) & Intel (`x86_64`)

The project uses standard Swift Package Manager (`Package.swift`). You can open the root directory directly in Xcode or build via terminal using `swift build`.

---

## License

By contributing to EXdl, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
