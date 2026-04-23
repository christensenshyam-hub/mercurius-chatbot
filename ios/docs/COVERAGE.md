# Coverage baseline

_Last refreshed: 2026-04-23 15:19:58Z_

Regenerate with:

```
cd ios && scripts/coverage.sh refresh-baseline
```

## Totals

| Surface | Line coverage |
|---|---|
| SPM packages (`swift test`) | 23.61% |
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
0  AppFeature              4              70.07% (206/294)   
1  ChatFeature             11             78.29% (2214/2828) 
2  DesignSystem            0              0.00% (0/0)        
3  Mercurius.app           1              100.00% (13/13)    
4  MercuriusTests.xctest   2              95.73% (448/468)   
5  MercuriusUITests.xctest 1              93.98% (203/216)   
6  NetworkingKit           0              0.00% (0/0)        
7  SettingsFeature         0              0.00% (0/0)        

```

## Files

- Full per-file SPM report: `build/coverage/spm-summary.txt`
- Full per-framework xcodebuild report: `build/coverage/xcode-summary.txt`
- Raw xcresult bundle: `build/coverage/xcode.xcresult` (open in Xcode for the interactive viewer)
