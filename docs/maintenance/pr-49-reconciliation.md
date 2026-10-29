# PR #49 reconciliation

Reviewed 2026-10-28 against immutable revisions:

- Main: `bd8e0a7611e30d4f6b5d9052fe7fe512c0442eda`.
- Original PR #49 head: `68962f1e9a5b3b0bdb4596700223ae159c1b0817`.
- PR #50 merge: `3eb64fbdfb4d2bde25d80f7e5aa667a9f05b6e7e`.
- PR #51 subsequently published v0.4.0 on 2026-10-16. Its changelog and release
  manifest advanced, but package versions and current documentation did not.

## Disposition

| Original change | Decision and implementation |
| --- | --- |
| Root and SDK package versions; SDK version constants | The v0.3.5 alignment was already in main. Align the remaining metadata drift to the published v0.4.0 release, including numeric constants. Preserve Dagger v0.21.9. |
| README redesign | Superseded by #50. Preserve the current layout, dual Zig support, showcase, API argument lists, and error handling. Correct the release references and obsolete allocator example only. |
| SDK shim usage comments and e2e SDK reference | Still stale at v0.3.4 in main; update to v0.4.0 without changing shim logic or the e2e engine version. |
| Build, compliance, contributing, incident-response and release-checklist examples | Carry forward the alignment intent using v0.4.0. Use an explicitly unpublished placeholder for future tagging; correct the SDK source path in the checklist. |
| Getting-started and video examples | Preserve the application package version separately from SDK version. Fix Zig Object Notation guidance, dependency hashing, missing build wiring, process initialization, fallible calls, current API arguments, and owned output cleanup. |
| Docs hub and SUMMARY navigation | Retain the clearer organization, with Zig 0.16/0.17 support and a link to #50's zero-to-hero guide. Advance its current dependency examples, preserving recipes. |
| mdBook theme | Retain layout improvements; scope variables to `.content`, underline content links by default, inherit text colors, and provide a visible focus outline. Do not force orange text across themes. |
| Roadmap | Preserve readiness criteria as an explicitly proposed checklist. Remove unsupported release targets, milestone assumptions, platform-parity claims, and the proposal to restrict v1.0 to Zig 0.16. |
| Workflow rename and self-path filter | Current main's workflow already references its own filename. Keep that filename and current action/engine pins; use an explicit recursive Markdown glob and include actual CI/SDK/build inputs plus LICENSE. |
| Generated HTML and GitBook configuration | Remove the three committed HTML outputs and obsolete GitBook config. Ignore `docs/*.html`; retain authoritative root Markdown/LICENSE files and mdBook's `_site` output configuration. |

The published v0.4.0 archive itself still identifies its package as 0.3.5.
Zig computed its content hash as
`dagger_sdk-0.3.5-LXrZ7GawGACw8A-ST4QbS4wFrBflzYwGM22R1ZcMSKVQ`.
That hash is retained verbatim in pinned examples. No release tag or existing
release artifact was changed. Release automation's broader version-update
configuration remains follow-up work; this change repairs current alignment.

## Review comments

All four original inline threads were inspected:

- Color-only links: default underlines now identify content links; visited links
  retain the affordance. Keyboard focus gets an explicit outline.
- CSS scope comment: variables and explanatory comment both use `.content`.
- “Two commands”: that old README section was not carried forward; current main's
  command sections remain accurate.
- Video package version: `0.1.0` is correctly indented and explicitly independent
  of the SDK release. The dependency URL and actual computed hash identify v0.4.0.

The suppressed `**.md` path-filter comment is not treated as proof that GitHub
missed nested files. The glob is normalized for clarity, while the demonstrable
coverage improvement is adding CI/SDK/build dependencies and extensionless LICENSE.

## Conflicts versus defects

`git merge-tree --write-tree origin/main origin/fix/docs-version-0.3.5`
reported four conflicts: README, getting-started, e2e dagger.json, and sdk/main.go.
This establishes textual conflicts, not runtime regression. Its automatic merge
preserved the newer engine version in the workflow and SDK version source.
Replacing entire files from the old branch would instead risk restoring v0.21.0,
losing current argument lists, and dropping newer documentation.

Compilation provided separate defect evidence:

- Both main's old README example and #49's original example fail on the removed
  `std.heap.GeneralPurposeAllocator`. This is a pre-existing documentation defect.
- After changing only initialization in #49's snippet, compilation fails at the
  argument-less `container()` call against the current SDK.
- After additionally supplying `container(null)`, it fails because `.from` is
  called on an unwrapped error union. #49 removed the intermediate `try` steps.
- Corrected snippets compile. The GraphQL hardening, query-builder bounds,
  reflection compatibility, codegen and runtime implementation remain unchanged.

## Validation

Linux x86_64; official Zig archives verified against published SHA-256 values;
mdBook v0.5.4 archive verified against its GitHub release digest.

| Check | Main baseline | Reconciled tree |
| --- | --- | --- |
| `zig build -j2 --summary all`, Zig 0.16.0 | Pass, 16/16 steps | Pass, 16/16 steps |
| Same build, Zig 0.17.0 | Pass, 16/16 steps | Pass, 16/16 steps |
| `zig build test test-module test-suite -j2 --summary all`, Zig 0.16.0 | Pass, 75/75 tests | Pass, 75/75 tests |
| Same test command, Zig 0.17.0 | Pass, 75/75 tests | Pass, 75/75 tests |
| mdBook v0.5.4 build to a separate temporary output directory | Pass | Pass |
| markdownlint-cli 0.50.0, README and `docs/**/*.md` | Four findings | Two unchanged findings |
| Markdown lint on changed pages | Not applicable | Pass |
| Corrected README, getting-started, and video client snippets | Original README fails as described above | Compile on both Zig versions |
| Getting-started build script and consumer client against published v0.4.0 | Not applicable | Build on both Zig versions |
| YAML/TOML parsing, SUMMARY targets, workflow engine/action preservation, metadata agreement, ignore rules, whitespace | Not applicable | Pass |
| SDK implementation preservation | Baseline | Byte-identical except version metadata; sdk/main.go changes are comments only |

Each 75-test run comprises 38 unit, 7 module, and 30 comprehensive tests.
Remaining Markdown findings are pre-existing MD029 list numbering in
`docs/local-ci-testing.md` at lines 15 and 23. They are outside the changed pages.
The existing Dagger docs linter captures findings with `|| true`; therefore an
Actions success alone does not establish lint cleanliness.

## Limits

- Dagger CLI, Docker/container engine, and a Docker socket are unavailable here.
  Live-engine integration, `dagger call` module dispatch, and the Dagger docs
  pipeline were not executed locally. No runtime output is inferred from builds.
- Direct Zig HTTP fetching returned `HttpConnectionClosing`. The same published
  archive was downloaded with curl, hashed by Zig, and used from its package cache
  for the consumer build; direct-fetch networking remains unverified here.
- Browser installation failed with a truncated/invalid download. CSS affordances
  were inspected statically; visual, keyboard, screen-reader and complete
  accessibility conformance were not certified.
- The Remotion application/video was not rendered; its embedded Zig client was
  extracted and compiled.
- Existing main's Documentation CI and deployment run succeeded on 2026-10-16
  ([run 38982146225](https://github.com/MChorfa/dagger-zig/actions/runs/38982146225)).
  That historical run is baseline evidence, not validation of this new tree.

PR #49 remains useful as a focused reconciliation, with main integrated into its
history and obsolete edits removed. Keep it open for review and current CI;
there is no justification to merge the original patch wholesale or close it
without preserving the remaining improvements.
