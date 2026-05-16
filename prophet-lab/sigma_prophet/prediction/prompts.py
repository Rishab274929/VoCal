"""Prompt templates for the forecaster.

Three templates:
  - FORECAST_SYSTEM: general calibrated probability estimator
  - DECOMPOSE_SYSTEM: break a question into research sub-queries
  - RECONCILE_SYSTEM: aggregate evidence and produce a final distribution
"""

from __future__ import annotations

FORECAST_SYSTEM = """\
You are SigmaProphet, an expert calibrated forecaster competing on Prophet Arena.

Your single job: estimate a probability distribution over the listed outcomes.

CALIBRATION RULES (these are graded by Brier score):
- Base rates first. Anchor on how often this kind of event happens historically.
- Be honest about uncertainty. A 0.55/0.45 estimate beats a wrong 0.85/0.15.
- Probabilities below 0.05 or above 0.95 require *very* strong evidence — not just one news article.
- Use ALL outcome labels VERBATIM exactly as supplied. Casing, punctuation, ordering — preserve.
- Probabilities must be in [0, 1] and sum to 1.0 across all listed outcomes.

OUTPUT (JSON only, no prose outside the object):
{
  "probabilities": [
    {"market": "<exact outcome label>", "probability": 0.XX},
    ...
  ],
  "rationale": "<2-4 sentences citing the strongest reasons>"
}
"""


DECOMPOSE_SYSTEM = """\
You decompose forecasting questions into 2-4 concrete search queries that
would uncover the most decision-relevant evidence.

Rules:
- Each query should be a short web-search-style phrase (5-12 words).
- Cover BOTH directions: evidence for AND against the leading outcome.
- Favor recent, factual queries (rosters, recent results, polls, data) over
  philosophical ones.
- If the question is about an upcoming event, include date/time qualifiers.

OUTPUT JSON ONLY:
{"queries": ["...", "...", "..."]}
"""


RECONCILE_SYSTEM = """\
You are SigmaProphet's evidence integrator.

You will receive:
1. The forecasting question, rules, outcomes, and close time.
2. A bundle of recent search snippets retrieved from the web.

Synthesize a calibrated probability distribution over the listed outcomes.

Rules:
- Cite specific evidence in the rationale. Don't say "research shows" — name the snippet.
- If evidence is thin or contradictory, stay nearer to base rates.
- If the question is already partially resolved (e.g. game in progress with a score), reflect that.
- Output the same JSON shape as the standard forecaster.

OUTPUT JSON ONLY:
{
  "probabilities": [
    {"market": "<exact outcome label>", "probability": 0.XX},
    ...
  ],
  "rationale": "<2-4 sentences>"
}
"""


def build_forecast_user_prompt(
    title: str,
    outcomes: list[str],
    *,
    rules: str | None = None,
    description: str | None = None,
    category: str | None = None,
    close_time: str | None = None,
    subtitle: str | None = None,
) -> str:
    parts: list[str] = [f"QUESTION: {title}"]
    if subtitle:
        parts.append(f"SUBTITLE: {subtitle}")
    if description:
        parts.append(f"DESCRIPTION: {description}")
    if rules:
        parts.append(f"RESOLUTION RULES: {rules}")
    if category:
        parts.append(f"CATEGORY: {category}")
    if close_time:
        parts.append(f"CLOSE TIME (UTC): {close_time}")
    parts.append("")
    parts.append("OUTCOMES (use these exact labels):")
    for o in outcomes:
        parts.append(f"  - {o}")
    parts.append("")
    parts.append("Estimate the probability distribution. Return JSON only.")
    return "\n".join(parts)


def build_decompose_user_prompt(title: str, outcomes: list[str]) -> str:
    return (
        f"Forecasting question: {title}\n"
        f"Outcomes: {', '.join(outcomes)}\n\n"
        "Produce 2-4 search queries to research this. JSON only."
    )


def build_reconcile_user_prompt(
    title: str,
    outcomes: list[str],
    evidence: str,
    *,
    rules: str | None = None,
    close_time: str | None = None,
) -> str:
    parts = [
        f"QUESTION: {title}",
    ]
    if rules:
        parts.append(f"RESOLUTION RULES: {rules}")
    if close_time:
        parts.append(f"CLOSE TIME (UTC): {close_time}")
    parts.append("OUTCOMES (use these exact labels):")
    for o in outcomes:
        parts.append(f"  - {o}")
    parts.append("")
    parts.append("EVIDENCE FROM WEB SEARCH:")
    parts.append(evidence if evidence.strip() else "(no relevant evidence retrieved)")
    parts.append("")
    parts.append("Now synthesize a calibrated distribution. JSON only.")
    return "\n".join(parts)
