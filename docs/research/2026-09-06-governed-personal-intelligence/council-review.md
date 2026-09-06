# Council Review — adversarial critique of the report

Run 2026-09-06 with the repo's `/council` skill: seven members, three rounds (independent analysis → anonymized cross-examination with an agreement-check counterfactual → final crystallization), confidence-weighted vote, synthesized by a non-deliberating Chairman. The verdict below is reproduced verbatim from the Chairman; the coordinator's notes and an addendum on the Open Knowledge Format follow it.

---

## Council Verdict

### Problem

A research report proposes "Governed Personal Intelligence": one person's principles, rules, lessons and decisions organized as a persistent, versioned, human-gated, self-evolving layer that many AI agents consult across many projects at low token cost — modelled on an enabling state (_chính phủ kiến tạo_) whose product is deterministic infrastructure (compiled enforcers, hooks, routed indexes) rather than runtime interpretation. Core claims: three content classes → three substrates; an L0–L6 authority ladder with forbid-overrides-permit; every law names an `enforcer` or declares itself `judgement`; a lifecycle experience → lesson → tallied candidate → human-merged law → constitutional proposal, where nothing promotes itself; a small custom layer (schema + compiler + lessons log + tally) over bought parts (git, hooks, AGENTS.md); and a four-week, two-project POC with five falsifiable hypotheses. The user asked three questions: is there a problem with the design, what should be added, and should the idea be upgraded and how.

### Council Composition

Seven members, three-round adversarial mode (independent analysis → anonymized cross-examination with a counterfactual/agreement-check trigger → final crystallization), with a confidence-weighted vote and a domain-weight seat.

- **Socrates** — assumption destruction; selected because the report's load-bearing claims (enforcer/judgement classification, "tallied evidence") are unexamined definitions.
- **Ada** — formal systems; selected because precedence resolution and promotion are claimed to be decidable algebra.
- **Meadows** — systems and feedback dynamics; **domain-weight seat (1.5×)**, because the report's central object is a lifecycle of stocks and flows.
- **Machiavelli** — power and incentives; selected because a single-principal governance system is a commitment problem.
- **Taleb** — tail risk and antifragility; selected because compiling one source into every agent perfectly correlates errors.
- **Torvalds** — shipping pragmatism; selected because nothing in the report is running code.
- **Karpathy** — empirical ML; selected because one step (correction → candidate law) is quietly LLM-judged.

### Chairman

Chairman: **Chairman** (anthropic · opus). Selection rationale: single-provider fallback — the chairman shares a provider with the panel and was not a deliberating member, so it synthesizes without having argued a position; no cross-provider chair was available.

### Provider Routing

| Member      | Provider  | Model                  |
| ----------- | --------- | ---------------------- |
| Socrates    | anthropic | opus (agent default)   |
| Ada         | anthropic | sonnet (agent default) |
| Meadows     | anthropic | sonnet (agent default) |
| Machiavelli | anthropic | sonnet (agent default) |
| Taleb       | anthropic | opus (agent default)   |
| Torvalds    | anthropic | sonnet (agent default) |
| Karpathy    | anthropic | sonnet (agent default) |
| Chairman    | anthropic | opus                   |

No fallbacks triggered. Ollama seats were deliberately not used: local models could not hold the ~700-line report at review quality. **Provider spread is therefore 1** — see the Epistemic Diversity Scorecard.

### Acceptable Compromises

- **We accept single-provider homogeneity.** Every seat ran on one provider, so a shared model prior may have produced part of the fast convergence on the retirement gap; the verdict trades provider diversity for the ability to actually read the full report.
- **We accept that no member measured anything.** The entire deliberation is textual criticism of an unbuilt system with zero hours of runtime; the verdict's confidence ceiling is "medium" everywhere except Karpathy's claim about already-live `/learn` behavior.
- **We accept slower first delivery.** Bundling retirement and a reviewer-capacity guard into the same commit as the schema (rather than deferring both) makes step 1 larger than Torvalds' minimal build, in exchange for never shipping a promotion-only system.
- **We accept leaving the sunset-versus-sampling question open.** The council could not decide whether silence should _retire_ a law or merely _flag_ it; the verdict specifies that a decay signal must exist and defers its mechanism to the user, rather than forcing a losing bet either way.
- **We accept keeping the enabling-state framing.** No member attacked the nation-state metaphor as such; the verdict does not relitigate the conceptual model even though Ada showed §2.2 uses two inconsistent stances on agent agency.

### Kill Criteria

- If, by **2026-10-04**, fewer than **3 real cross-level conflicts** can be counted in CLAUDART's own history where plain conjunction ("all checks must pass") gave the wrong answer, the precedence-engine recommendation is invalidated and we should build Socrates' installable **checker package** instead of the L0–L6 compiler, with prose as a generated README.
- If, by the end of the four-week POC, the `proposals/` directory or the lessons log in **either** pilot project goes unreviewed past 30 days, the verdict is invalidated and we should kill the compiler/tally, keep only the enforcer-tagging discipline, and downgrade cross-project consistency to manual file-copying (Machiavelli's counterfactual, and his own preferred test).
- If **more than 50% of laws** are marked `judgement` at the end of the POC, the "enforce, don't explain" premise (§12.1) is not the product — prose compilation is — and the enforcer-first architecture in §7 should be re-derived.
- If **H1 or H2 fails with real numbers** by the end of the POC, steps 4–10 of §15 must not be started; the concept is not worth pursuing in this form (the report's own stated condition, which the council endorses).
- If a **classification-agreement rate** measured over ≥20 real corrections across two independent extraction passes exceeds **0.9**, Karpathy's instrumentation prerequisite is falsified and the tally's input may be trusted without the extra gate.
- If a **deliberately wrong law** (Taleb's H6) is not retired within 30 days of being planted, the retirement machinery does not work regardless of what the schema says, and the whole promotion pipeline should be frozen at step 3.

### Concrete Next Step

**Write a revision of the report (`README.md` v2 plus `poc.md` v2) that folds retirement, a reviewer-capacity budget, and the corrected metrics into the design — amending §2.4, §10, §11, §15 step 1 and poc §3.1/§4 — by 2026-09-13.**

### Unresolved Questions

Leading with what the council does **not** know:

1. **Does the conflict problem exist at all?** Nobody, in three rounds, could name a single case in CLAUDART's history where two rules at different authority levels collided such that plain conjunction gave the wrong answer. The L0–L6 ladder, the precedence resolver, the static conflict check and H5 all inherit this emptiness if the count is zero. **This is the single highest-value input the user can supply** and it is cheap to gather.
2. **What is the actual reviewer-hours budget?** The council proved that one human's PR bandwidth is the binding constraint (Meadows Loop 2, Machiavelli), but nobody knows the number. Without it, "rate-limit proposal generation to what a solo reviewer can clear" has no parameter.
3. **Should silence retire a law or only flag it?** Taleb's fail-closed `sunset:` and Socrates' objection ("a non-firing secret-scan law is _working_, not stale — absence-of-events cannot discriminate obsolete from successfully deterrent") are both correct within their own frames. This is a risk-preference call the user must make: pay a recurring re-ratification tax on every correct law, or accept a sampling process that can miss.
4. **What fraction of the intended corpus is genuinely enforceable?** If most laws are judgement-shaped, the compiler's value collapses toward prose distribution, which off-the-shelf tools (Ruler/rulesync) already do.
5. **How many projects and agents are really in scope?** H3's cross-project claim and the "many agents" framing were never grounded in a count; two projects sharing a template may be one observation (Taleb).
6. **Is the report's own cost estimate real?** Torvalds showed §16's "on the order of `constitution-check.sh` plus `claudart-graph.sh`" is asserted, not derived — a 5-target compiler with a correctness-critical resolver whose bugs are silent was never sized.
7. **What resolves the §9/§15.5 contradiction?** Taleb flagged that "git pull at session start" (§9) contradicts the pinned-revision model (§15 step 5); no other member addressed it, and the report does not settle which wins. An unreviewed upstream law reaching a running session is compile-once, break-everywhere.

### Recommended Next Steps

In priority order, after the single Concrete Next Step:

1. **Count the conflicts (the gate).** Sweep CLAUDART's git history and rule corpus for real cross-level collisions; record the count in a committed evidence file. `≥3` → the precedence engine is earned; `0` → cut it and build the checker package. Anchors: README §2.4, §7 commitment 3, poc §1 (H5).
2. **Delete the `confidence:` field.** It has no stated producer, no calibration and no consumer — the tally counts lessons, not confidence-weighted lessons. It is an unsupported abstraction that a human reviewer will misread as validation. Anchors: poc §3.2, README §10.
3. **Split `enforcer` from `authority-weight` into two independent frontmatter fields.** §2.4's resolution rule 3 conflates enforcement-mechanism with deliberative authority, letting a trivially-scripted convention outrank a deeply-considered judgement law at the same level and scope. Uncontested by any member. Anchors: README §2.4 rule 3, poc §3.1.
4. **Add a decay/retirement term to the law schema and ship it in the same commit as the schema itself** — not as a later phase. Whichever mechanism the user picks (fail-closed `sunset:` or `silent-since:` + sampled review), it must be independent of override/contradiction evidence, because a working enforcer extinguishes exactly those signals. Anchors: README §10 (the two named demotion triggers), §12.1, §13; poc §3.1; §15 step 1.
5. **Ship the reviewer-capacity guard in that same commit.** A proposal rate-limit sized to the stated hours budget, plus `expires:` on unmerged proposals, plus **median proposal age** and **reviewer-hours** as first-class POC metrics. Retirement machinery without triage capacity converts silent entrenchment into silent backlog collapse. Anchors: README §11 (regime table), poc §4 (metric table).
6. **Replace "deterministic catch rate" with seeded-violation recall.** The current metric's denominator is "violations found by any means," so it _rises when review degrades_ — it measures attention, not compliance, and cannot fail honestly. Inject N known violations per law and count catches. Anchors: poc §4, README §11 step 2 (negative controls).
7. **Instrument the classification step now, in parallel with steps 1–3 — not after H1/H2.** Require the correction → candidate-law step to justify itself against the existing law corpus retrieval-style rather than from free recall, log disagreement when two passes tag the same correction differently, and track **classification-agreement rate** as a POC metric. This step is already live in `/learn` today (README §3's audit admits promotion criteria are agent-judged), so deferring it leaves the tally's input silently miscounted for the whole phase-1 window. Anchors: README §3, §10; poc §3.2, §4.
8. **De-duplicate the tally by provenance pointer and require ≥1 deterministic-signal lesson** (enforcer exit, failed gate, user correction) before any threshold crossing. As written, three flags from one agent habit count as three projects' worth of evidence — the design distrusts agent judgement enough to forbid autonomous promotion, then computes the promotion trigger from agent judgement. Anchors: README §10, poc §3.3.
9. **Make the phase gate external, not aspirational.** Machiavelli's point stands: the compiler itself must hard-stop past §15 step 3 absent a committed evidence file with real H1/H2 numbers. A self-imposed gate is a plan, not a gate — and this is the one part of a governance system that currently has no enforcer governing it. Anchors: README §15, §13, §16.
10. **Add the counter-tally and H6.** `enforcer_fired_then_human_completed_anyway` as an explicit falsification channel, and a sixth hypothesis: _a deliberately wrong law is retired within 30 days._ Untested retirement is the exposure. Anchors: poc §1, §4; README §10.
11. **Blind the H4 reviewer to proposal origin.** Comparing tallied proposals against unassisted `/learn` proposals while knowing which is which measures enthusiasm, not acceptance. Anchor: poc §1 (H4), §4.
12. **Resolve the §9/§15.5 pull-versus-pin contradiction in writing**, and add `not-covered:` per law (what its enforcer misses, re-required whenever `digest` changes) — the latter carried at lower priority because Torvalds credibly argues it is a maintenance tripwire on a solo operator before any compiler exists.

### Consensus & Agreement

**Formally: no consensus** — no option cleared the 2/3 threshold, so the decision escalates to the user. But the split is narrower than the tally suggests, and three things did survive all three rounds unanimously:

1. **Build something.** All seven members reject `do-not-build`. Nobody argued the design is fundamentally wrong.
2. **The retirement gap is real and structural.** Five members reached it by four independent routes — Meadows' _Fixes-that-Fail_ loop (enforcement suppresses the override/contradiction signals that §10 needs to demote a law), Ada's formal finding (the promotion algebra has an addition operator and no defined subtraction, so it is not closed under its own claimed reversibility), Taleb's exposure argument (a law correct in 2026 and wrong in 2027 emits _no event_ while being enforced corpus-wide), and Machiavelli's incentive version (a bored reviewer produces telemetry identical to a healthy system). This is the report's central defect.
3. **Reviewer capacity is the binding constraint, and the fixes for (2) all push against it.** Meadows' second loop is the one contribution that changed other members' positions: a demotion operator, a sunset field and a decay flag _all add inflow to the same fixed review stock_. Ada, Machiavelli, Socrates and Taleb all explicitly adopted the sequencing conclusion — decay and capacity must land in the same phase, not sequentially.

The coordinator's note is correct and load-bearing: the three backed options are compatible in content, not contradictory. Torvalds folds sunset/decay into steps 1–3 and defers only the tally, precedence engine and capacity guard; Karpathy accepts deterministic compilation proceeding in parallel and insists only that the live classification step be measured now. **The disagreement is about sequencing and first-build scope, not about whether to build.**

**Answering the user's three questions explicitly:**

- **Is there a problem with the design?** Yes — one structural and four specific. Structural: the lifecycle is a promotion pipeline with no working retirement path, and the enforcement mechanism that makes the design valuable is the same mechanism that starves its own correction signal. Specific: (a) §2.4 rule 3 conflates two independent axes; (b) poc §3.2's `confidence:` field has no producer or consumer; (c) poc §4's catch-rate metric cannot fail honestly; (d) the tally treats correlated agent self-reports as independent evidence. None of these is fatal; all are cheap to fix before any code exists.
- **What should be added?** Twelve items, listed in Recommended Next Steps, each anchored to the section it changes. The four that the council would not ship without: a decay term in the law schema (§10, §15 step 1, poc §3.1), a reviewer-capacity guard shipped with it (§11, poc §4), the `enforcer`/`authority-weight` split (§2.4), and deletion of `confidence:` (poc §3.2).
- **Should the idea be upgraded, and how?** Yes — by making the design **symmetric**. The report's finest principle, _"nothing promotes itself,"_ currently has no twin. Upgrade it to _"nothing promotes itself, and nothing entrenches itself silently"_: promotion and demotion become one artifact, shipped together, never separately. Two supporting upgrades follow. First, change the unit of success from tokens saved to **net reviewer-hours** — a governance layer that saves 30% of boot context while consuming more of the same person's time than it returns is a loss the current metric suite cannot detect. Second, move the report's honesty about undecidability (§1.2) one level up: the design already admits natural-language conflict detection is undecidable, and should equally admit that _its own maintenance loop_ is the one subsystem with no enforcer — then give it one.

### Vote Tally

Confidence-weighted tally (STEP 6). Base weights: Meadows 1.5× (domain-weight seat, systems/feedback design), all others 1.0. Confidence factor: high 1.0 · med 0.75 · low 0.5.

- `build-with-retirement` — **4.125** (Meadows [1.5× domain, med → 1.125, DEALBREAKER: yes], Socrates [med → 0.75], Ada [med → 0.75], Machiavelli [med → 0.75], Taleb [med → 0.75])
- `instrument-then-build` — 1.0 (Karpathy [high → 1.0])
- `build-minimal-first` — 0.75 (Torvalds [med → 0.75])
- `checker-package-first` — 0 (raised as a counterfactual by Socrates; no final backer)
- `do-not-build` — 0 (raised as a counterfactual by Machiavelli; no final backer)

W_total 7.5 · threshold (2/3) = 5.0 · **no option clears the threshold → formally no consensus; escalated to the user.**

Coordinator note: the three backed options are largely compatible in content, not contradictory — Torvalds folds sunset/decay into steps 1-3 and only defers the tally/precedence engine/capacity guard; Karpathy accepts deterministic compilation in parallel and only insists the live classification step be measured first. The split is about sequencing and scope of the first build, not about whether to build. All seven reject "do-not-build" and none backs "checker-package-first" after the counterfactual round, though Socrates carries its evidence test forward as a gate (≥3 counted real cross-level conflicts before the precedence engine is written).

### Key Insights by Member

- **Socrates**: The design's metrics push against the one quantity nobody measures — how much of a law its enforcer actually covers — so the cheapest way to pass H2 is to reclassify judgement laws as enforceable behind a weak grep; and he alone asked the question that could invalidate the largest component, _how many cross-level conflicts has the precedence engine ever needed to resolve?_
- **Ada**: The promotion algebra has an addition operator and no defined subtraction, so it is not closed under the reversibility §10 claims; separately, §2.4's rule 3 folds enforcement-mechanism and deliberative authority into one ordering position, which is a modeling error rather than a policy choice.
- **Meadows** (domain seat): Named both loops that decided the verdict — enforcement suppresses the very override and contradiction events that would trigger a law's re-examination (_Fixes-that-Fail_), and every proposed fix for that adds inflow to a review stock fixed at one person's bandwidth (_Limits to Growth_) — concluding that decay and capacity are one structural fix, not two features.
- **Machiavelli**: The beneficiary of every layer above L4 is future-you and the cost-bearer is present-you, with no contributor pool to share review load; and the design's own philosophy — _a law with no enforcer is a suggestion_ — is violated precisely once, by its own maintenance loop, where a stale `proposals/` directory has no checker, no state and no alarm.
- **Taleb**: Per-event harm is bounded but errors are perfectly correlated by design, so the real exposure is _duration × correlation_ — a law correct in 2026 and wrong in 2027 produces silent, permanent, corpus-wide compliance while emitting no event at all; his H6 (a deliberately wrong law is retired within 30 days) is the only proposed test of the retirement path itself.
- **Torvalds**: The strongest evidence in the report is the audit of what already runs, and everything else is a future experiment — approving a ten-step migration for a system with zero hours of measured runtime is the failure mode, and §16's cost estimate names two existing scripts without comparing them to a 5-target compiler whose resolver bugs are silent.
- **Karpathy**: The one place LLM judgement still governs what gets counted — correction → `candidate_law` — is already running in production today and is unmeasured; it will shortcut toward matching salient _existing_ law ids, so genuinely novel recurring patterns fragment across three tags and never reach the ≥3 threshold, a rich-get-richer promotion bias invisible in the design.

### Points of Disagreement

- **Does silence retire, or only flag?** Taleb: mandatory fail-closed `sunset:`, because a flag produces a queue and the queue has one reviewer and no enforcer. Socrates: silence cannot discriminate an obsolete law from a successfully deterrent one — the two emit identical signal — so default expiry bills the reviewer for every _correct_ law and amplifies the very backlog Taleb's `expires:` tries to cure. Meadows sits between them (flag for sampling); Ada requires only that the decay term be independent of usage evidence. **Irreconcilable within the council; escalated as Unresolved Question 3.**
- **Is a symmetric demotion operator a fix or symmetry theater?** Ada proposed one; Meadows and Taleb both argued it is well-formed and will never fire, because it is fed by exactly the signal enforcement extinguishes. Ada conceded the point in Round 3 without withdrawing the operator.
- **Process before code, or code before process?** Socrates' four additions (`not-covered:`, seeded-violation recall, provenance dedup, blinded H4) versus Torvalds' objection that a recall harness is a test suite for a system with zero hours of runtime. Partially resolved — Socrates dropped "the ceremony" in Round 3 — but the `not-covered:` tripwire remains contested.
- **When to instrument the classifier.** Karpathy: now, because it is live today. Torvalds: after H1/H2, because everything else is scaffolding. This is the entire distance between the two minority stances, and it is one metric's worth of work.
- **Barbell versus token savings.** Socrates argued Taleb's "90% judgement-only prose, never an enforcer on a judgement-shaped law" restores at runtime exactly the token cost §12.1 exists to remove — trading the design's only proven win against an unmeasured risk. Unresolved.
- **Can a solo operator game themselves?** Socrates hedged that "a person cannot game themselves for long"; Machiavelli called this backwards — solo operators self-deceive _longer_ than groups, with no colleague to say the metric is gamed. Machiavelli's version prevailed in the room but Socrates never formally conceded.

### Minority Report

**Meadows — DEALBREAKER: yes (the only one).** Shipping the compiler _without_ the decay counter and a reviewer-hours cap in the same phase is not an acceptable partial delivery. Strongest argument: the two failure modes are not independent — ship enforcement without a decay signal and wrong laws survive indefinitely with zero visible symptom; ship decay without triage capacity and silent entrenchment simply becomes silent backlog collapse. Sequencing them converts one failure into the other rather than fixing either. This dealbreaker is why the verdict's Concrete Next Step is a design revision rather than a build task.

**Torvalds — `build-minimal-first`.** Ship §15 steps 1–3 only (schema, validator, one compile target, zero-diff regeneration against today's hand-written files), with sunset folded in because it is one frontmatter field rather than new machinery; gate everything else on real H1/H2 numbers. Strongest argument: the report itself is honest that none of this runs, so the objection is not to the plan but to approving ten steps at once — and §16's cost estimate for a 5-target compiler with a silent-failure resolver is asserted rather than derived. He accepts Machiavelli's correction that the gate must be enforced by the compiler hard-stopping at step 3, since a self-imposed gate is aspiration.

**Karpathy — `instrument-then-build` (the only high-confidence vote in the room).** The agent-judged classification step is not a future risk of a system to be built; it is `/learn`'s live behavior today, admitted by the report's own audit. Strongest argument: every other option in the room defers measuring the one component that is already running and already unreliable, which means shipping the genuinely low-risk deterministic layer while the tally's input stays silently miscounted for the entire phase-1 window. His ask is small and parallel — delete `confidence:`, add a classification-agreement metric now — which is why the verdict adopts it as Recommended Next Step 7 despite its single-member backing.

**Counterfactual 1 — `checker-package-first` (raised by Socrates, no final backer).** Make the _enforcer_ the unit of reuse, not the law: ship one installable checker package (hooks, scripts, negative controls) that any agent runs, and let prose become a generated README. This deletes the schema, the precedence engine and the tally in one move, because executable checks compose by conjunction — all must pass — so "a narrower scope may tighten, never loosen" comes free rather than being engineered. Falsifiable inside the POC's four weeks: count real cross-level conflicts the compiler resolves that conjunction would not (≥3 → build the compiler; 0 → it is machinery for an absent problem); run H3 twice, hand-copied CLAUDART versus the compiled layer (equal non-zero start → the layer buys nothing); measure the share of laws marked `judgement` (>50% → prose compilation _is_ the product and this alternative fails). Socrates abandoned the stance but carried its first test forward as a hard gate, which the verdict adopts as Kill Criterion 1.

**Counterfactual 2 — `do-not-build` (raised by Machiavelli, no final backer).** Treat CLAUDART itself as the reusable unit: copy `.claude/` into new projects verbatim, edit prose by hand, and let agent-judged `/learn` remain the only promotion path. Strongest argument: in a single-principal system this wins by default, because one person cannot sustainably be legislature, courts and archivist at once, and every hour spent tallying lessons is an hour not spent shipping the software the tool exists to accelerate. Its own falsifier is the verdict's second Kill Criterion — if the pilot's `proposals/` queue goes stale past the self-decay threshold, that is direct proof the pipeline costs more reviewer-time than it saves. Machiavelli withdrew it on the evidence of the repo's demonstrated, sustained self-governance (a maintained constitution, fail-closed checkers and LEDGER discipline already running), which he called counter-evidence to his own thesis.

### Epistemic Diversity Scorecard

- **Perspective spread: 5/5** — epistemics, formal algebra, systems dynamics, incentive analysis, tail risk, shipping pragmatism and empirical ML each produced a distinct, non-redundant finding, and four of the seven reached the central defect by genuinely different routes rather than by agreement.
- **Provider spread: 1/5** — every seat, and the chairman, ran on a single provider across two model tiers. Ollama seats were excluded on capability grounds. This is the verdict's main structural weakness.
- **Evidence mix:** ~10% empirical (only Karpathy's claim that `/learn` already runs agent-judged classification, plus the report's audit of what exists) / ~45% mechanistic (Meadows' loops, Ada's algebra, Taleb's correlation argument, Karpathy's shortcut-learning) / ~25% strategic (Machiavelli's incentive map, Meadows' and Socrates' sequencing, capacity as binding constraint) / 0% ethical (no member raised privacy, autonomy or the ethics of self-binding — a genuine blind spot) / ~20% heuristic (Torvalds' shipping priors, Meadows' archetype naming, Taleb's barbell).
- **Convergence risk: High.** Single provider, one shared source text, and the room collapsed onto one finding — the retirement gap — inside a single round, with cross-examination mostly _reinforcing_ it rather than testing it. Both counterfactuals were self-generated by members who then abandoned them, so no position argued against the majority to the end. The strongest mitigation is that the convergent finding was derived four independent ways and is checkable against §10 and §12.1 of the report directly; the strongest residual worry is Socrates' unanswered conflict-count question, which nobody but its author pressed, and the complete absence of an ethical lens on a system designed to bind its author's future judgement.

### Follow-Up

After acting on this verdict, revisit: Was this verdict useful? Was the recommended action taken? What happened? Specifically, re-open this file once the conflict count from Kill Criterion 1 exists (target 2026-10-04) and again at the end of the four-week POC window, and record: the counted number of real cross-level conflicts; the measured net reviewer-hours; the share of laws marked `judgement`; whether a deliberately wrong law was retired within 30 days; and whether the `proposals/` queue in either pilot went stale. Any one of those five results is sufficient to overturn a section of this verdict, and three of them can overturn the recommendation to build the compiler at all.

---

### Session Metadata

```
schema_version: 1
mode: full (custom 7-member panel)
panel_size: 7
rounds_run: 3 (+ restate gate, + 2 counterfactual prompts from the agreement check)
chairman_failed_fallback: no
tools_used: yes   # members read the report files; no file was modified
input_tokens_estimate: ~unknown
output_tokens_estimate: ~unknown
duration_seconds: ~1500
provider_count: 2 (anthropic used; ollama detected but not seated)
fallbacks_triggered: none
```

---

## Coordinator's notes

- **Framing warning from the restate gate.** Four of seven members reframed the problem away from architecture toward operability before reading the report: who keeps the pipeline fed, whether bad rules get retired, whether the human gate becomes the bottleneck. The verdict confirms that reframing was correct.
- **What the council did not examine.** No member evaluated the landscape's project choices, the security model (§13), or the MCP phase; the critique is concentrated on §2.4, §10, §11, §12 and the POC metrics. The ethical lens (self-binding, privacy of lessons) was absent and is recorded as a blind spot.
- **Status of the report.** The Concrete Next Step was executed the same day: the twelve amendments are applied as v2 in `README.md` (§2.4, §7, §8, §9, §10, §11, §15, §16, §18) and `poc.md` (§1–§5). Default chosen for the open sunset-versus-sampling question: fail-soft degradation on `stale_after` expiry (status → `draft`, enforcer → `warn` after a 30-day grace, one queue item), with fail-closed sunset one flag away; the user then delegated the choice ("whatever is best long-term and correct"): expiry is fail-soft tiered by `authority`. The conflict count (kill criterion 1) was gathered the same day, see `conflict-count.md`: three hard collisions, all resolved at authoring time, so precedence becomes compile-time declaration checking and no runtime resolver is built.

---

## Addendum — Open Knowledge Format (OKF) and `okf-agent-memory`

Checked 2026-09-06 at the user's request. This is a real gap in the landscape: the report did not cover OKF.

**The format.** The Open Knowledge Format is a Google Cloud specification (repository `GoogleCloudPlatform/knowledge-catalog`, Apache-2.0, v0.1 published 2026-06-12, now v0.2) for packaging knowledge as a directory of Markdown files with YAML frontmatter, cross-linked into a graph, with `index.md` files for progressive disclosure and `log.md` for dated changes. It is a format, not a service. Its v0.2 frontmatter families map almost one-to-one onto this report's needs:

| OKF v0.2 field family                                                                     | What it gives                                                                                                                   | Maps to in this report                                                                                        |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `sources[]` with `resource`, `author`, `usage_count`, `last_modified`, `usage_window`     | provenance with objective credibility signals; per-claim attribution by id                                                      | R7 provenance; the `evidence:` links on a law                                                                 |
| `generated.by` / `generated.at`, `verified[] {by, at}`                                    | who produced and who checked content; **trust tiers** derived mechanically: unverified → machine-confirmed → **human-reviewed** | the approval event on a law (`verified.by: human:<id>` _is_ the human gate); knowledge `status`               |
| actor convention `human:<id>` · `<producer>/<version>` · `process:<id>`                   | consumers key trust off the `human:` prefix; producers must not claim human verification for agent output                       | the orchestrator-only / worker-never-writes rule, made visible in data                                        |
| `status: draft \| stable \| deprecated`                                                   | lifecycle                                                                                                                       | the law and knowledge lifecycles                                                                              |
| `stale_after: <absolute instant>`                                                         | staleness as a plain comparison, no TTL arithmetic                                                                              | **the council's retirement/decay term** — the field already exists in a published spec                        |
| `type: Attested Computation` with `runtime`, `parameters`, `executor.receipt`, `attester` | a sanctioned computation plus a **deterministic, non-LLM check** that a run followed it                                         | the report's `enforcer:` concept, generalized: OKF fixes the interface, the packaging (skill, script) is free |

**Assessment.** OKF is the strongest candidate found for the _knowledge_ substrate's frontmatter standard, and its trust-tier and `stale_after` semantics answer two council findings directly (human-gated verification as data; a decay term independent of usage evidence). It does not model authority levels, precedence, or norm promotion, so it does not replace the law schema; it should be adopted _under_ it. Concretely: express `.claude/knowledge/` topics as an OKF bundle (the existing frontmatter — `status`, `sources`, `verify`, `last_verified` — is already close), and reuse `generated` / `verified` / `stale_after` on laws rather than inventing `since` / `sunset` / evidence fields from scratch. Vendor neutrality and an Apache-2.0 spec from a major cloud make it a safer bet than any single memory tool.

**The tool, `okf-memory/okf-agent-memory`.** MIT, pure Go with zero dependencies, ~15 MB, sub-4 ms cold start; validates an OKF bundle (graph connectivity, description drift), BM25 lexical search with no embeddings, `create`/`update` with automatic `log.md` and `index.md` bookkeeping, `bootstrap` into any repo (writes `.agents/skills/okf-memory/` and AGENTS.md instructions), and an MCP server over stdio for Claude Code, Cursor and Codex. Its convention document adds search-before-write, a knowledge-review step after substantial work, a rule that agents must never mark content human-verified, and human override. It stores semantic knowledge only (facts, decisions, observations, discoveries); no rules, no authority, no promotion. **Maturity: created 2026-09-05, two commits, one author, one release (v0.1.0), 227 stars in its first day.** Verdict: the _shape_ is exactly the "checker package + routed index + MCP resource" the report and the council both point at. **User decision 2026-09-06: adopt it for the knowledge layer.** Local trial the same day: builds from source with Go 1.25 (`go build ./cmd/okf`, ~3.9 MB binary), `go test ./...` passes, `okf validate` on its own corpus and on the software example exits 0, a missing `type` makes it exit 1 (negative control), a broken link is a warning unless `--strict` (then exit 1), BM25 `search` returns ranked hits with match fields, `bootstrap` writes `AGENTS.md`, a `Makefile`, `knowledge/{index,log}.md` and a six-file `.agents/skills/okf-memory/` skill, and the MCP server completes the handshake and lists `okf_search, okf_show, okf_validate, okf_create, okf_update, okf_relate`. Two cautions carried into the design: the MCP surface includes write tools, so it must run over `knowledge/` only and never over `laws/`; and at two commits and one author, files remain the source of truth so the tool can be dropped without loss, with a maintenance re-check monthly.

Sources: [Google Cloud OKF announcement coverage](https://www.marktechpost.com/2026/06/16/google-cloud-introduces-open-knowledge-format-okf-a-vendor-neutral-markdown-spec-for-giving-ai-agents-curated-context/) · [OKF spec](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) · [GitBook explainer](https://www.gitbook.com/blog/what-is-okf-open-knowledge-format) · [okf-agent-memory](https://github.com/okf-memory/okf-agent-memory) (metadata via the GitHub API on 2026-09-06).
