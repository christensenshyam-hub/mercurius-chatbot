# Coverage baseline

_Last refreshed: 2026-04-23 13:41:22Z_

Regenerate with:

```
cd ios && scripts/coverage.sh refresh-baseline
```

## Totals

| Surface | Line coverage |
|---|---|
| SPM packages (`swift test`) | 21.99% |
| Xcode app target (`xcodebuild test`) | 100.00% |

## Two pathways, one codebase

Every file is potentially exercised by two independent test
pipelines — read the numbers as MAX(SPM, xcodebuild), not as
either one alone:

- **SPM** (`swift test` on macOS) covers view models, networking,
  persistence, parsers — anything that doesn't need a SwiftUI
  runtime. Reports per-file % with line coverage.
- **xcodebuild** on iOS Simulator covers views through
  snapshot + XCUITest. Reports per-framework % aggregated across
  all files in each package product.

Known rows to ignore:

- `NetworkingKit  0  0.00% (0/0)` in the xcodebuild table is the
  empty `*_PackageProduct` wrapper, not the module. NetworkingKit
  is thoroughly covered by the SPM pathway — see spm-summary.txt.
- `SnapshotTesting` low coverage is expected — we ship our code
  through that library, we don't test its internals.

## Per-framework (xcodebuild)

```
ID Name                    # Source Files Coverage           
-- ----------------------- -------------- ------------------ 
0  ChatFeature             11             36.53% (1033/2828) 
1  ClubFeature             6              45.49% (343/754)   
2  Mercurius.app           1              100.00% (13/13)    
3  MercuriusTests.xctest   2              94.86% (240/253)   
4  MercuriusUITests.xctest 1              93.98% (203/216)   
5  NetworkingKit           0              0.00% (0/0)        

```

## Files

- Full per-file SPM report: `build/coverage/spm-summary.txt`
- Full per-framework xcodebuild report: `build/coverage/xcode-summary.txt`
- Raw xcresult bundle: `build/coverage/xcode.xcresult` (open in Xcode for the interactive viewer)
