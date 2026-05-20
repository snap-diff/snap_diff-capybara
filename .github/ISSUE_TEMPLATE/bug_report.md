---
name: Bug report
about: Create a report to help us improve screenshot comparisons
title: ''
labels: bug
assignees: ''

---

## Describe the bug

A clear and concise description of what the bug is.

## To Reproduce

Steps to reproduce the behavior:

1. Go to '...'
2. Click on '...'
3. Run `....`
4. See error

## Expected behavior

A clear and concise description of what you expected to happen.

## Actual behavior

What actually happened. Include the full error message and stack trace if applicable.

## Screenshots

If applicable, add the `.diff.png` or `.heatmap.diff.png` files to help explain the problem.

## Environment

- **Ruby version:** (e.g., 3.4.1)
- **Rails version:** (e.g., 8.0) or N/A (non-Rails project)
- **`capybara-screenshot-diff` version:** (e.g., 1.12.0)
- **Image processing driver:** (`:vips` or `:chunky_png`)
- **Capybara driver:** (e.g., `selenium_chrome_headless`, `cuprite`)
- **Operating system:** (e.g., macOS 14, Ubuntu 24.04)
- **CI environment:** (e.g., GitHub Actions, local only)

## Configuration

```ruby
# Your test helper configuration (omit sensitive parts)
```

## Debug output

If applicable, run with `DEBUG=1` and paste the output:

```
DEBUG=1 bundle exec rake test
```

## Additional context

Add any other context about the problem here. For example:
- Is it specific to CI vs local?
- Does it reproduce with both VIPS and ChunkyPNG drivers?
- Is this a regression from a previous version?
