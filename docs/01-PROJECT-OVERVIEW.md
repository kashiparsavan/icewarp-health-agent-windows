# 01 - Project Overview

**Project:** IceWarp Health Agent for Windows
**Audit date:** 2026-11-01
**Audited commit:** `2e6694b` (branch `HEAD`, tag `windows-v0.1.7` + 2 doc commits)
**Auditor:** OpenCode (worker role, per `CLAUDE.md` section 13)
**Scope:** `windows/agent.ps1`, `windows/lib/`, `windows/collectors/`, `windows/tests/`,
`windows/config/checklist.conf.pdf`, `docs/api-key-mapping.md`, and the project documentation.

---

## 1. What the project is

The IceWarp Health Agent for Windows is a standalone Windows PowerShell 5.1 tool. It runs on
an IceWarp mail server and does four things:

1. **Collects** about 430 configuration and runtime values. Sources are `tool.exe`, CIM/WMI,
   the registry, DNS queries, and live network probes (SMTP STARTTLS, TLS on port 443, RBL
   lookups, and a public-IP lookup).
2. **Evaluates** these values against the IceWarp Checklist v1.14 in a health engine. The
   results are written as `health.*` keys and rolled up into nine executive pillars.
3. **Exports** a flat, sorted JSON file (`output/health.json`). The file follows the 432-key
   schema of the Linux agent, so both agents can feed the same monitoring stack.
4. **Renders** two PDF reports when the agent runs with `-Report`: a technical checklist report
   and an executive (management) report. The PDFs are written by hand-built PDF code with no
   external dependencies.

The Windows agent is independent of the Linux agent (`CLAUDE.md` section 14). The two share no
code and no runtime calls, and they are versioned separately (`windows-v*` tags).

## 2. Key facts

| Item | Value (measured during this audit) |
|---|---|
| Runtime target | Windows PowerShell 5.1 (Server 2012 R2+, Windows 10/11) |
| Version in `windows/VERSION` | **0.1.7** |
| Version in root `VERSION` / `CLAUDE.md` | 0.1.5 (out of date) |
| Latest git tag | `windows-v0.1.7` |
| Collector scripts | 27 (`General/` 1, `Icewarp/` 26), 2,431 lines |
| Library code | 9 files, 4,523 lines (631 of them in the dead file `Report.ps1`) |
| Tests | 1 Pester file, 28 `It` blocks, 1,100 lines |
| Schema keys (fixture) | 432 |
| Keys emitted in a live dev run | 433 (all 432 schema keys plus 1 extra key, `health.disk.archive.message`) |
| Pester result on PS 5.1 / Pester 3.4.0 | **27 passed, 1 failed** (the version test expects `0.1.6`) |
| `agent.ps1 -Report` on PS 5.1 | **Fails, exit 1.** JSON is written; no PDFs are produced (see `03-CODE-AUDIT.md`, B-01) |
| `agent.ps1 -Report` on PS 7.4 | PDFs are produced, according to `windows/logs/agent.log` |

## 3. Repository layout (as it actually exists)

```
icewarp-health-agent-windows/
├── CLAUDE.md                     Rules, architecture, agent protocol
├── README.md, CHANGELOG.md, VERSION (0.1.5)
├── agents_bridge.md              OMP <-> OpenCode task ledger (some headings have broken encoding)
├── tool.v14.3.0.13.windows.help  Windows APIConst.pas reference
├── docs/
│   ├── api-key-mapping.md        432-key mapping (sections disagree with each other, see 03)
│   ├── api-windows-vs-linux-v14.3.0.13.md
│   ├── api-update-v14.3.0.12-to-14.3.0.13.md
│   ├── REVIEW.md                 Historical review (v0.1.1 era)
│   └── 01..05-*.md               This audit
└── windows/
    ├── agent.ps1                 Entry point
    ├── VERSION (0.1.7), README.md, CHANGELOG.md
    ├── config/agent.example.psd1, checklist.conf.pdf (plain text, "~"-delimited, 113 rows)
    ├── docs/deployment.md        (CLAUDE.md says this file is at docs/deployment.md)
    ├── lib/                      Common, Config, Logging, IceWarpTool, Json, Health,
    │                             ReportTechnical, ReportManagement, Report (dead duplicate)
    ├── collectors/General/Version.ps1
    ├── collectors/Icewarp/*.ps1  (26 files)
    └── tests/Agent.Smoke.Tests.ps1, Run-Tests.ps1, fixtures/schema-keys.json
```

## 4. Module map

| Module | Files | Responsibility | Status at a glance |
|---|---|---|---|
| Entry point | `agent.ps1` | CLI, locking, orchestration | Works. PDF failures abort the run with exit 1. |
| Core libs | `Common`, `Config`, `Logging`, `IceWarpTool`, `Json` | Context, isolation, tool wrapper, JSON writer | Solid and well tested |
| Collectors | 27 scripts | Data gathering | All 432 keys covered; 9 collectors have value bugs |
| Health engine | `Health.ps1` | Rules, roll-ups, nine pillars | Complete; 4 logic defects; core rules not unit-tested |
| PDF renderers | `ReportTechnical.ps1`, `ReportManagement.ps1` | Technical and executive PDFs | Broken on PS 5.1; thresholds drift from `Health.ps1` |
| Tests | `tests/` | Pester contract tests | 27/28 pass; no PDF or end-to-end coverage |
| Docs | root + `docs/` + `windows/` | User and agent documentation | Thorough but out of date in places |

## 5. Headline findings

1. **The JSON contract is the strongest part.** All 432 schema keys are emitted with the right
   types, and the JSON writer matches the Linux coercion rules exactly.
2. **The PDF reports do not work on the target runtime.** `ReportTechnical.ps1:235` uses a
   `Join-Path` form that only exists in PowerShell 7. On PS 5.1, `-Report` exits 1 after the
   JSON is written.
3. **Collector isolation breaks cross-collector dependencies.** Each collector runs in its own
   runspace with an empty `$Context.Data`. As a result `MySQL.ps1` can never detect MySQL.
4. **`$host` is a read-only automatic variable.** `DatabaseType.ps1` and `MySQL.ps1` assign to
   it, so they throw on any MySQL deployment.
5. **The PDF renderers break Rule 3.2 (renderer sync).** CPU, disk, OS-update, admin-email,
   license and directory-cache rows use different logic from `Health.ps1`.
6. **Version and documentation drift.** Four different version numbers appear in the repo,
   and the changelogs stop at 0.1.4 (root) and 0.1.5 (`windows/`).

## 6. Overall completion

**About 60% complete** (weighted: collectors 72%, health engine 74%, PDF renderers 37%,
tests 39%, docs 65%). `04-PROGRESS-REPORT.md` explains how these numbers were calculated.
`05-ROADMAP-NEXT-STEPS.md` lists the prioritized plan.

## 7. Related documents

- `02-ARCHITECTURE-AND-FLOW.md` - runtime flow, data contracts, design decisions
- `03-CODE-AUDIT.md` - every bug and piece of tech debt, with file:line evidence
- `04-PROGRESS-REPORT.md` - completion percentage per module and method
- `05-ROADMAP-NEXT-STEPS.md` - prioritized next steps
