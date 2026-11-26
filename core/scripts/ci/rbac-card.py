#!/usr/bin/env python3
"""Build the Adaptive Card that rbac.yml posts into the Teams chat with the subscription owner.

Kinds:
  request  role assignment changes wait for approval (amber)
  drift    the weekly run found Azure no longer matches grants.yaml (amber)
  result   what happened after the approval step (green when applied, red otherwise)

Reads the change list from CHANGES (the JSON written by rbac-changes.sh; names only) and the context from:
  ACTOR, EVENT, SHA, RUN_URL                the GitHub run
  PR_NUMBER, PR_TITLE, PR_URL               the pull request behind the commit, if any
  RESULT, REASON, APPROVERS                 result cards only: the apply job's result, "changed" when the list
                                            differed from the request, and who approved or rejected the run
Writes the card (the "content" part of the Teams message) to stdout.

Usage: CHANGES=... RUN_URL=... python3 core/scripts/ci/rbac-card.py request|drift|result
"""

import json
import os
import sys

MAX_ROWS = 30
WHERE = "NEBo resource groups only, never the subscription"
ACTIONS = {
    "add": ("＋ add", "Good"),
    "remove": ("－ remove", "Attention"),
    "change": ("± change", "Warning"),
}


def env(name, default=""):
    return os.environ.get(name, "").strip() or default


def text(value, **extra):
    block = {"type": "TextBlock", "text": value, "wrap": True}
    block.update(extra)
    return block


def row(cells, header=False, color=None):
    widths = ["auto", 3, 4, 4]
    columns = []
    for i, (cell, width) in enumerate(zip(cells, widths, strict=True)):
        block = text(cell, weight="Bolder" if header else "Default")
        if color and i == 0:
            block["color"] = color
        columns.append({"type": "Column", "width": width, "items": [block]})
    return {"type": "ColumnSet", "spacing": "Small", "columns": columns}


def change_table(changes):
    items = [text("Changes", weight="Bolder", spacing="Medium"), row(["", "Identity", "Role", "Scope"], header=True)]
    for change in changes[:MAX_ROWS]:
        label, color = ACTIONS.get(change["action"], (change["action"], None))
        items.append(row([label, change["principal"], change["role"], change["scope"]], color=color))
    if len(changes) > MAX_ROWS:
        items.append(text("… and {} more, listed in the run.".format(len(changes) - MAX_ROWS), isSubtle=True))
    return items


def counts(changes):
    adds = sum(1 for c in changes if c["action"] == "add")
    edits = sum(1 for c in changes if c["action"] == "change")
    removes = sum(1 for c in changes if c["action"] == "remove")
    return adds, edits, removes


def breakdown(adds, edits, removes):
    """'7 to add, 0 to remove', with 'N to change' between them only when there are changes."""
    parts = ["{} to add".format(adds)]
    if edits:
        parts.append("{} to change".format(edits))
    parts.append("{} to remove".format(removes))
    return ", ".join(parts)


# Role assignments can only change in place in their description (NEBo sets no conditions).
CHANGE_NOTE = " A change only updates an assignment's description; the role, scope and identity stay the same."


def plural(n, word):
    return "{} {}{}".format(n, word, "" if n == 1 else "s")


def change_fact(event, pr_number, pr_title):
    if pr_number:
        return "PR #{} · {}".format(pr_number, pr_title) if pr_title else "PR #{}".format(pr_number)
    if event == "schedule":
        return "grants.yaml on main (weekly check)"
    if event == "workflow_dispatch":
        return "Manual run on main"
    return "Commit on main"


def request_sentence(kind, changes):
    adds, edits, removes = counts(changes)
    note = CHANGE_NOTE if edits else ""
    if kind == "drift":
        return (
            "The weekly check found that NEBo's role assignments in Azure no longer match grants.yaml. "
            "Approving the run restores them: {}. Nothing changes until you approve it "
            "in GitHub.{}".format(breakdown(adds, edits, removes), note)
        )
    if removes == 0 and adds == len(changes):
        return (
            "NEBo asks for **{}** in your subscription. "
            "Nothing is assigned until you approve the run in GitHub.".format(plural(adds, "role assignment"))
        )
    if adds == 0 and removes == len(changes):
        return "NEBo asks to **remove {}**. Nothing changes until you approve the run in GitHub.".format(
            plural(removes, "role assignment")
        )
    return (
        "NEBo asks for **{}** to role assignments in your subscription: {}. "
        "Nothing changes until you approve the run in GitHub.{}".format(
            plural(len(changes), "change"), breakdown(adds, edits, removes), note
        )
    )


def result_sentence(result, reason, changes):
    if result == "success":
        verb = "was" if len(changes) == 1 else "were"
        return "**{}** {} applied as approved.".format(plural(len(changes), "change"), verb)
    if reason == "changed":
        return (
            "Nothing was applied: the list of changes was different by the time the run was approved. "
            "Run the rbac workflow again for a new request."
        )
    if result == "cancelled":
        return "The run was cancelled before it applied anything, for example because the approval timed out."
    return (
        "The request was rejected, or the run failed. Open the run to see which. If it failed while applying, "
        "the log lists any change made before it stopped."
    )


def build(kind):
    changes = json.loads(env("CHANGES", "[]"))
    event = env("EVENT")
    sha = env("SHA")[:7]
    run_url = env("RUN_URL")
    pr_number, pr_title, pr_url = env("PR_NUMBER"), env("PR_TITLE"), env("PR_URL")

    if kind == "result":
        result, reason = env("RESULT"), env("REASON")
        applied = result == "success"
        style = "good" if applied else "attention"
        title = "NEBo · Role assignments applied" if applied else "NEBo · Role assignment request not applied"
        facts = [
            ("Change", change_fact(event, pr_number, pr_title)),
            ("Commit", sha),
            ("Approval", env("APPROVERS", "none recorded")),
        ]
        body = [text(result_sentence(result, reason, changes))]
        actions = [{"type": "Action.OpenUrl", "title": "Open the run", "url": run_url}]
    else:
        style = "warning"
        title = "NEBo · Role assignment drift found" if kind == "drift" else "NEBo · Role assignment approval needed"
        requested_by = "Weekly drift check" if event == "schedule" else env("ACTOR", "unknown")
        facts = [
            ("Requested by", requested_by),
            ("Change", change_fact(event, pr_number, pr_title)),
            ("Commit", sha),
            ("Where", WHERE),
        ]
        body = [text(request_sentence(kind, changes))]
        actions = [{"type": "Action.OpenUrl", "title": "Review and approve", "url": run_url, "style": "positive"}]
        if pr_url:
            actions.append({"type": "Action.OpenUrl", "title": "View the pull request", "url": pr_url})

    body.append({"type": "FactSet", "facts": [{"title": t, "value": v} for t, v in facts if v]})
    body.extend(change_table(changes))
    if kind != "result":
        body.append(text("What to do", weight="Bolder", spacing="Medium"))
        body.append(text("Open the run, check the list, then **Review deployments → Approve** (or Reject)."))
        body.append(
            text(
                "Owner, User Access Administrator and Role Based Access Control Administrator are refused before a "
                "request reaches you. If the list changes after this card was sent, the run stops instead of applying.",
                isSubtle=True,
                size="Small",
            )
        )

    header = {
        "type": "Container",
        "style": style,
        "bleed": True,
        "items": [text(title, weight="Bolder", size="Large")],
    }
    return {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "msteams": {"width": "Full"},
        "body": [header] + body,
        "actions": actions,
    }


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("request", "drift", "result"):
        sys.exit(__doc__.strip().splitlines()[-1])
    json.dump(build(sys.argv[1]), sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
