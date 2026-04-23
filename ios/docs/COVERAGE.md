# Coverage baseline

_Last refreshed: 2026-04-23 06:28:16Z_

Regenerate with:

```
cd ios && scripts/coverage.sh refresh-baseline
```

## Totals

| Surface | Line coverage |
|---|---|
| SPM packages (`swift test`) | 21.99% |
| Xcode app target (`xcodebuild test`) | 100.00% |

## Per-framework (xcodebuild)

Covers everything linked into the test-run process, including the
SPM packages that the app embeds. Third-party packages (e.g.
`SnapshotTesting`) appear with low coverage because we exercise
our own code through them, not their internals.

```
ID Name                    # Source Files Coverage          
-- ----------------------- -------------- ----------------- 
0  AppFeature              4              70.07% (206/294)  
1  ChatFeature             11             26.38% (746/2828) 
2  ClubFeature             6              45.49% (343/754)  
3  Mercurius.app           1              100.00% (13/13)   
4  MercuriusTests.xctest   2              92.35% (157/170)  
5  MercuriusUITests.xctest 1              93.52% (202/216)  
6  NetworkingKit           0              0.00% (0/0)       
7  SnapshotTesting         28             15.48% (916/5919) 

```

## Files

- Full per-file SPM report: `build/coverage/spm-summary.txt`
- Full per-framework xcodebuild report: `build/coverage/xcode-summary.txt`
- Raw xcresult bundle: `build/coverage/xcode.xcresult` (open in Xcode for the interactive viewer)

## Scope notes

- SPM coverage ignores `.build/`, `Tests/`, and `Fixtures/` dirs.
- SPM-only tests run with `swift test` on macOS. The xcodebuild
  run exercises the same modules from the iOS simulator, so
  numbers differ by pathway rather than being strictly additive.
- Views that are only rendered through SwiftUI surface (most
  `*View.swift` files) score 0% on the SPM side because SPM
  tests don't boot a SwiftUI runtime. They're covered by the
  xcodebuild snapshot + UI test run instead.
