// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/test;

// ***** Mocked evaluation tests *****
//
// Both the agent under evaluation and the LLM judge are replaced with mocks, so
// every scenario runs deterministically, offline, and without a model provider
// or credentials. No test in this module makes a real LLM call.

// Mirrors the judge output shape the LLM-judge evaluations expect from `generate()`.
type MockVerdict record {|
    float evalScore;
    string judgeReasoning;
|};

// Builds an agent whose `run()` always produces a trace carrying the given response.
function mockAgent(string mockResponse) returns ai:Agent {
    ai:Agent agentMock = test:mock(ai:Agent);
    ai:Trace mockTrace = {
        id: "mock-trace",
        userMessage: {role: "user", content: "mock query"},
        iterations: [],
        output: {role: "assistant", content: mockResponse},
        tools: [],
        startTime: [0, 0.0],
        endTime: [1, 0.0]
    };
    test:prepare(agentMock).when("run").thenReturn(mockTrace);
    return agentMock;
}

// Builds a judge whose `generate()` always returns the given verdict.
//
// `ai:Wso2ModelProvider` is used purely as the concrete stand-in type required by
// `test:mock`; no service URL or access token is involved, because the mock never
// calls the real provider's `init` or reaches the network.
function mockJudge(float evalScore, string judgeReasoning) returns ai:ModelProvider {
    ai:Wso2ModelProvider judgeMock = test:mock(ai:Wso2ModelProvider);
    MockVerdict mockVerdict = {evalScore, judgeReasoning};
    test:prepare(judgeMock).when("generate").thenReturn(mockVerdict);
    return judgeMock;
}

// ***** LLM-judge scenarios *****

// A judge score above the threshold passes the evaluation.
@test:Config {
    groups: ["mock-evaluations", "llm-judge"]
}
function judgeAboveThresholdPasses() returns error? {
    check evaluateHelpfulness(targetAgent = mockAgent("The answer is 2."), queries = "what is 1 + 1",
            judgeModel = mockJudge(0.9, "mock: very helpful"), judgeScoreThreshold = 0.75);
}

// A judge score exactly at the threshold passes: the comparison is `>=`, not `>`.
@test:Config {
    groups: ["mock-evaluations", "llm-judge"]
}
function judgeAtExactThresholdPasses() returns error? {
    check evaluateHelpfulness(targetAgent = mockAgent("The answer is 2."), queries = "what is 1 + 1",
            judgeModel = mockJudge(0.75, "mock: just helpful enough"), judgeScoreThreshold = 0.75);
}

// A judge score below the threshold fails, and the returned error carries the
// metric name, the query, the score, and the judge's reasoning.
@test:Config {
    groups: ["mock-evaluations", "llm-judge"]
}
function judgeBelowThresholdFails() {
    error? evalResult = evaluateHelpfulness(targetAgent = mockAgent("Some unhelpful text."),
            queries = "what is 1 + 1", judgeModel = mockJudge(0.25, "mock: does not help the user"),
            judgeScoreThreshold = 0.75);
    if evalResult is () {
        test:assertFail("expected the evaluation to fail when the judge score is below the threshold");
    }
    string failureMessage = evalResult.message();
    test:assertTrue(failureMessage.includes("[helpfulness]"), "metric name missing from failure");
    test:assertTrue(failureMessage.includes("what is 1 + 1"), "query missing from failure");
    test:assertTrue(failureMessage.includes("0.25"), "judge score missing from failure");
    test:assertTrue(failureMessage.includes("mock: does not help the user"),
            "judge reasoning missing from failure");
}

// ***** Rule-based scenarios *****

// A response length inside the configured bounds passes.
@test:Config {
    groups: ["mock-evaluations", "rule-based"]
}
function lengthWithinBoundsPasses() returns error? {
    check assertLengthCompliance(targetAgent = mockAgent("The answer is 2."), queries = "what is 1 + 1",
            minLength = 1, maxLength = 100);
}

// A response longer than `maxLength` fails, and the error reports the actual
// length together with the configured range.
@test:Config {
    groups: ["mock-evaluations", "rule-based"]
}
function lengthOutsideBoundsFails() {
    error? evalResult = assertLengthCompliance(targetAgent = mockAgent("This response is far too long."),
            queries = "what is 1 + 1", minLength = 1, maxLength = 5);
    if evalResult is () {
        test:assertFail("expected the evaluation to fail when the response exceeds maxLength");
    }
    string failureMessage = evalResult.message();
    test:assertTrue(failureMessage.includes("[length-compliance]"), "metric name missing from failure");
    test:assertTrue(failureMessage.includes("30"), "actual response length missing from failure");
    test:assertTrue(failureMessage.includes("[1, 5]"), "configured range missing from failure");
}
