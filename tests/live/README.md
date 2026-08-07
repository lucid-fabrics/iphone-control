# Live suite + benchmark

Runs real gestures against the connected iPhone through iPhone Mirroring.
Every test is a phone-state no-op: the screen must be identical before and after.

## Preconditions (the recipe)

1. iPhone Mirroring open, phone connected and unlocked
2. Phone on **home screen, page 1**, portrait
3. An icon present at row 5 slot 1 (content point 54,555) - used by the drag test
4. Hands off mouse and keyboard for the whole run (the idle-guard defers actions
   while you type or move the mouse, which skews timings)
5. No Focus-mode banners mid-screen (status-bar icons are fine)

## Commands

```bash
# Single pass - functional check (~25s)
tests/live/run-live.sh

# Benchmark - N passes with per-test success rate and min/median/max timing
tests/live/run-live.sh --bench 5
```

Raw per-test results land in `tests/live/results/bench-<timestamp>.jsonl` (gitignored).

## What each test proves

| Test | Proves |
|------|--------|
| find-window | window + content-bounds detection, cache path |
| screenshot-dims | capture pipeline; point-normalized output matches content size |
| tap-noop | tap lands; screen unchanged; **cursor and focus restored** |
| ocr-find | screenshot → Vision OCR → text matching (tap-text --dry on "Search") |
| page-swipe | drag-swipe page navigation there and back |
| icon-drag-lift | full icon lift/track/drop cycle (dynamics recipe), zero layout change |

## Reading results

- Any FAIL: check the printed detail; `results/*.jsonl` has one row per test per iteration.
- Success rate below 100% on `icon-drag-lift` = drag dynamics regressing - inspect
  before touching `ICON_DRAG_SPEED` or hover timings in `helpers/common.sh`.
- Timing regressions: compare medians between two JSONL files; medians are stable,
  maxes are noisy (Spotlight indexing, iOS animations).

## When to re-run

- After touching `helpers/common.sh` timing/dynamics constants
- After macOS or iOS updates (mirroring input handling has changed between versions)
- Before trusting a new gesture pattern - add it here as a no-op test first
