# 0001. Work tracker: GitHub Issues + Project

- **Status:** accepted
- **Date:** 2026-11-15

## Context

The NEBo tasks need a work-tracking system for three things:

- **Planning and estimation:** every stage, task and work item with an estimate, and the actual time recorded when it closes.
- **CI/CD integration (Task 2):** builds linked to tickets, and ticket status updated from the CI/CD outcome.
- **Troubleshooting (Task 6):** one ticket per case, with the root-cause analysis and the preventive measures linked to tickets.

The code is in a public GitHub repository with GitHub Actions. The evaluator must be able to see the tracker without an account. The task descriptions accept either Jira or GitHub Issues.

## Options considered

| | GitHub Issues + Project | Jira Cloud (Free) |
|---|---|---|
| Cost | Free | Free up to 10 users, with limited automation runs |
| Linking to code | Built in: `Fixes #N` closes the issue on merge; commits and PRs appear on the issue | Needs the GitHub for Jira app and issue keys in branch, commit and PR names |
| CI/CD updates | `GITHUB_TOKEN` for issues; one personal access token for Project fields | REST API with an API token, or Jira Automation rules |
| Hierarchy | Sub-issues (up to 8 levels) and blocked-by links | Epics, sub-tasks, configurable link types |
| Workflow | Status field on the Project plus built-in automations | Fully configurable states and transitions |
| Estimates | Number fields (Estimate h, Actual h) with sums per group | Built-in original estimate vs logged time, sprints, burndown |
| Reporting | Project views and simple charts | JQL and dashboards, much richer |
| Visibility | Public with the repository; no account needed | The evaluator needs an invited seat, or screenshots |

## Decision

Use **GitHub Issues** for all work items, with sub-issues for the hierarchy, and one public **GitHub Project** ("NEBo") for planning fields and views:

- **Hierarchy:** stage → task → work item. Labels replace issue types, because issue types need a GitHub organization.
- **Project fields:** Status, Stage, Estimate h, Actual h, Target date, Release.
- **Views:** Board, Estimates, Roadmap, Incidents, Releases.
- **Delivery:** one PR per work item, closing it with `Fixes #N`.
- **Issue forms:** `work` and `incident`, with blank issues turned off.

## Consequences

- **No extra service, account or secret** for basic tracking, and the evaluator can open everything from the repository.
- **Estimates don't add up to the parent automatically.** Totals come from grouped sums in the Estimates view, so hours go on work items only.
- **CD needs one extra secret to update Project fields.** `GITHUB_TOKEN` cannot access a user-owned Project, so a classic personal access token with only the `project` scope is stored on the `prod` environment and rotated before it expires.
- **Reporting is simpler than Jira's.** That is acceptable for one person and eight tasks.
- **Jira can be reconsidered** if the work moves to a team that already uses it. The issue history can then be imported.
