# Contributing

Thanks for contributing to RTL Bus Tracker.

## How to Contribute

1. Fork the repository and create a feature branch.
2. Keep changes focused and small.
3. Run checks locally before opening a PR.
4. Open a pull request with a clear summary and testing notes.

## Local Checks

```bash
flutter format .
flutter analyze
flutter test
```

## Code Guidelines

- Follow existing Flutter/Dart style and architecture.
- Prefer clear naming over clever abstractions.
- Add or update tests when behavior changes.
- Do not commit secrets, local machine config, or generated build artifacts.

## Pull Request Checklist

- [ ] Code is formatted
- [ ] Analyzer passes
- [ ] Tests pass (or reason documented)
- [ ] README/docs updated when behavior changes
- [ ] No unrelated file changes
