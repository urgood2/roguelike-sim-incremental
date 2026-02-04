# QA Report - 2026-02-04

## Build Status
- [x] Builds successfully (100% Built target raylib-cpp-cmake-template)
- Deprecation warnings present but no errors

## Test Summary
- Total: Unknown (tests did not run)
- Passed: N/A
- Failed: N/A
- Skipped: N/A
- **BLOCKED**: Tracy Profiler initialization failure - "CPU doesn't support invariant TSC"

### Test Infrastructure Issue
Tests compiled successfully but failed to execute due to:
```
Tracy Profiler initialization failure: CPU doesn't support invariant TSC.
Define TRACY_NO_INVARIANT_CHECK=1 to ignore this error, *if you know what you are doing*.
Alternatively you may rebuild the application with the TRACY_TIMER_FALLBACK define to use lower resolution timer.
```

## UBS Scan
- Critical: 995 (all in third-party code - bootstrap.min.js loose equality)
- Warnings: 9138 (mostly third-party code)
- Info: 12382
- Notes: No actionable critical issues in project code. All flagged items are in vendored third-party dependencies.

## Open Beads
- Open: 0
- In Progress: 0
- Completed: 216
- Blocked: 0

## Verdict
[ ] READY TO SYNC - All checks pass
[x] NEEDS FIXES - See issues above

### Blocking Issues
1. **Tests cannot run** - Tracy Profiler CPU requirement not met on this machine
   - This is an infrastructure/CI environment issue, not a code issue
   - Options: Build with `TRACY_TIMER_FALLBACK` or `TRACY_NO_INVARIANT_CHECK=1`

## Created Beads
- `bd-23th`: Fix: Tests fail to run due to Tracy Profiler CPU TSC requirement (P2, bug)

## Recommendations
1. For sync to proceed, either:
   - Run tests on a machine with invariant TSC support, OR
   - Rebuild tests with `TRACY_TIMER_FALLBACK` define
2. The build itself is successful and stable
3. No critical code issues detected - all UBS criticals are in third-party vendored code
