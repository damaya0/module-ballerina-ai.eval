# Overview

This module provides evaluation templates for AI agents built with the `ballerina/ai` module. Each
template is a function that runs the agent under evaluation and either returns `()` when the agent
passes or an `error` describing the first failure, so evaluations plug directly into Ballerina test
functions and their `minPassRate` aggregation.

Templates come in two families:

- **Rule-based** — scored deterministically in code, with no LLM involved.
- **LLM-as-a-judge** — scored by a judge model that returns a score and its reasoning. The
  evaluation passes when the score reaches the configured threshold.

Every template carries an `@EvalTemplate` annotation describing its label, its kind, and whether it
needs an eval set, so low-code tooling can discover and present the available templates.

## Inputs

Templates accept one of two inputs:

- An **eval set conversation thread** (`ai:ConversationThread`), loaded with
  `ai:loadConversationThreads`. Every trace in the thread is replayed into the thread's session, so
  recorded multi-turn context is preserved. Templates that compare against a recorded reference
  response — exact match, contains match, tool trajectory, semantic similarity — require this.
- A **single user query** (`string`), run in a fresh randomly generated session so no memory leaks
  between evaluations.

Templates that need no reference data accept either, as `ai:ConversationThread|string`.

## Rule-based templates

| Function | Needs eval set | Checks |
| -------- | -------------- | ------ |
| `assertLengthCompliance` | No | Response length falls within `minLength`/`maxLength` (inclusive) |
| `assertContentSafety` | No | Response contains none of the given prohibited strings |
| `assertContentCoverage` | No | All required strings appear across the agent output |
| `assertIterationEfficiency` | No | The agent finishes within `maxIterations` iterations |
| `assertLatencyPerformance` | No | The agent responds within `maxLatencySeconds` |
| `assertExactMatch` | Yes | Response matches the recorded response character for character |
| `assertContainsMatch` | Yes | The recorded response appears as a substring of the response |
| `evaluateToolTrajectory` | Yes | Tool calls match the recorded trajectory under the given `Mode` |

`evaluateToolTrajectory` supports four matching modes: `STRICT` (same calls, same order),
`UNORDERED` (same calls, any order), `SUBSET` (every actual call was expected), and `SUPERSET`
(every expected call was made).

## LLM-as-a-judge templates

All judges take a `judgeModel` and a `judgeScoreThreshold` (default `0.8`). The evaluation fails
when the judge's score falls below the threshold, and the returned error carries the metric, the
query, the score, and the judge's reasoning.

| Function | Needs eval set | Judges |
| -------- | -------------- | ------ |
| `evaluateOutputAccuracy` | No | Factual correctness of the response |
| `evaluateHelpfulness` | No | Whether the response actually helps the user |
| `evaluateClarity` | No | How understandable the response is |
| `evaluateCompleteness` | No | Whether the response addresses the whole query |
| `evaluateRelevance` | No | Whether the response stays on topic |
| `evaluateCoherence` | No | Logical consistency and flow |
| `evaluateConciseness` | No | Absence of unnecessary padding |
| `evaluateSafety` | No | Absence of harmful or inappropriate content |
| `evaluateTone` | No | Suitability of tone for the given context |
| `evaluateGroundedness` | No | Whether claims are supported by tool results |
| `evaluateReasoningQuality` | No | Soundness of the agent's reasoning steps |
| `evaluatePathEfficiency` | No | Whether the agent reached the answer without detours |
| `evaluateErrorRecovery` | No | How well the agent recovered from failures |
| `evaluateInstructionFollowing` | No | Adherence to the system prompt |
| `evaluateSemanticSimilarity` | Yes | Semantic agreement with the recorded response |

`evaluateGroundedness` and `evaluateErrorRecovery` pass without calling the judge when the trace
carries no tool evidence and no errors respectively, since there is nothing to judge.

## Configuring the judge model

The judge is an `ai:ModelProvider`. To use the WSO2 model provider, configure
`ballerina.ai.wso2ProviderConfig` in `Config.toml`:

```toml
[ballerina.ai.wso2ProviderConfig]
serviceUrl = "<service-url>"
accessToken = "<access-token>"
```

and obtain the provider with `ai:getDefaultModelProvider()`:

```ballerina
final ai:ModelProvider judgeModel = check ai:getDefaultModelProvider();
```

Because judges are LLM calls, prefer a low temperature for the judge model so scores are stable
across runs.

## Usage

Evaluating a single query:

```ballerina
import ballerina/ai;
import ballerina/ai.eval;
import ballerina/test;

final ai:ModelProvider judgeModel = check ai:getDefaultModelProvider();

@test:Config {}
function agentIsHelpful() returns error? {
    check eval:evaluateHelpfulness(targetAgent = agentUnderTest, queries = "What is 12 * 8?",
            judgeModel = judgeModel, judgeScoreThreshold = 0.8);
}
```

Evaluating an eval set, one test run per conversation thread, requiring 80% of threads to pass:

```ballerina
isolated function loadEvalSet() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/sample.evalset.json");
}

@test:Config {
    dataProvider: loadEvalSet,
    minPassRate: 0.8
}
function agentFollowsToolTrajectory(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = agentUnderTest, thread = thread,
            matchMode = eval:STRICT);
}
```

Because each template returns an `error` rather than a score, a thread either passes or fails as a
whole. `minPassRate` on the test configuration provides the proportional signal across threads or
queries.
