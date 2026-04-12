# Test Fixture Images

These images are used by the unit test suite for image comparison testing.

| File | Description |
|------|-------------|
| `a.png` | Base island map (80x80) |
| `b.png` | Modified island map — small region differs from `a.png` |
| `c.png` | Modified island map — different region differs from `a.png` |
| `d.png` | Modified island map — another variation |
| `a_cropped.png` | Cropped version of `a.png` |
| `portrait.png` | Portrait orientation image (3x6) |
| `portrait_b.png` | Modified portrait — differs from `portrait.png` |
| `a.webp` | WebP version of `a.png` |

## Generated artifacts (gitignored)

These files are generated during test runs and should NOT be committed:

| Pattern | Description |
|---------|-------------|
| `*.diff.png` | Annotated diff overlay |
| `*.base.diff.png` | Annotated base image |
| `*.heatmap.diff.png` | Heatmap of pixel differences |
