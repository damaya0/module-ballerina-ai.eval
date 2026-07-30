// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
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
import ballerina/time;
import ballerina/uuid;

// ***** Rule-based evaluations *****

# Checks that agent response lengths fall within the given bounds (inclusive).
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + minLength - The minimum accepted response length (inclusive)
# + maxLength - The maximum accepted response length (inclusive)
# + return - `()` if every checked response passes, or an error describing the first failure
@EvalTemplate {
    label: "Length Compliance",
    description: "Checks that agent response lengths stay within the configured bounds",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertLengthCompliance(ai:Agent targetAgent, ai:ConversationThread|string queries,
        int minLength = 1, int maxLength = 10000) returns Error? {
    if queries is string {
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkLength(userQuery = queries, actualResponse = actualResponse,
                minLength = minLength, maxLength = maxLength);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = queries.id);
        check checkLength(userQuery = userQuery, actualResponse = actualResponse,
                minLength = minLength, maxLength = maxLength);
    }
}

# The matching strategies supported by the tool-trajectory evaluation.
public enum TrajectoryMatchMode {
    # The agent must make exactly the reference tool calls, in the same order
    STRICT,
    # The agent must make exactly the reference tool calls, in any order
    UNORDERED,
    # The agent may only make tool calls that appear in the reference (no extras);
    # it does not have to make all of them
    SUBSET,
    # The agent must make at least all the reference tool calls; extra calls are allowed
    SUPERSET
}

# Checks the agent's tool calls against the trajectory recorded in the eval set.
# A tool call matches when both the tool name and its arguments are equal;
# tool-call IDs are ignored since they differ between runs.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + matchMode - The trajectory matching strategy to apply
# + return - `()` if every trace passes, or an error describing the first mismatch
@EvalTemplate {
    label: "Tool Trajectory",
    description: "Checks the agent's tool calls against the eval set trajectory using a configurable matching mode",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function evaluateToolTrajectory(ai:Agent targetAgent, ai:ConversationThread thread,
        TrajectoryMatchMode matchMode = STRICT) returns Error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = userQuery, sessionId = thread.id);
        ai:FunctionCall[] expectedToolCalls = expectedTrace.toolCalls ?: [];
        ai:FunctionCall[] actualToolCalls = actualTrace.toolCalls ?: [];
        if !matchTrajectory(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls,
                matchMode = matchMode) {
            return error(string `[tool-trajectory] query "${userQuery}": tool calls do not satisfy ` +
                    string `${matchMode} matching; expected ${describeToolCalls(toolCalls = expectedToolCalls)} ` +
                    string `but got ${describeToolCalls(toolCalls = actualToolCalls)}`);
        }
    }
}

# Checks that every agent response exactly matches the expected response recorded
# in the eval set. Every character must match, apart from leading/trailing
# whitespace when `stripWhitespace` is set.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + caseSensitive - Whether the comparison is case-sensitive. When `false`, only ASCII
# A–Z is folded, so non-ASCII letters still compare case-sensitively
# + stripWhitespace - Whether to strip leading/trailing whitespace before comparing
# + return - `()` if every trace matches, or an error describing the first mismatch
@EvalTemplate {
    label: "Exact Match",
    description: "Checks that each agent response exactly matches the expected response in the eval set",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function assertExactMatch(ai:Agent targetAgent, ai:ConversationThread thread,
        boolean caseSensitive = true, boolean stripWhitespace = true) returns Error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check traceOutput(trace = expectedTrace);
        string rawExpected = expectedOutput.content ?: "";
        string rawActual = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = thread.id);
        string expectedResponse = stripWhitespace ? rawExpected.trim() : rawExpected;
        string actualResponse = stripWhitespace ? rawActual.trim() : rawActual;
        if !caseSensitive {
            expectedResponse = expectedResponse.toLowerAscii();
            actualResponse = actualResponse.toLowerAscii();
        }
        if actualResponse != expectedResponse {
            int mismatchIndex = findFirstMismatch(expectedResponse = expectedResponse,
                    actualResponse = actualResponse);
            return error(string `[exact-match] query "${userQuery}": responses differ at character ` +
                    string `index ${mismatchIndex} (expected lengths ${expectedResponse.length()}, ` +
                    string `actual ${actualResponse.length()}); expected ` +
                    string `"…${excerptAround(text = expectedResponse, mismatchIndex = mismatchIndex)}…" ` +
                    string `but got "…${excerptAround(text = actualResponse, mismatchIndex = mismatchIndex)}…"`);
        }
    }
}

# Checks that agent responses contain none of the prohibited strings. For a thread,
# one offending response fails the whole thread. An empty prohibited list is a
# configuration error and fails.
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + prohibitedStrings - The strings that must not appear in any agent response
# + caseSensitive - Whether the matching is case-sensitive. When `false`, only ASCII
# A–Z is folded, so non-ASCII letters still compare case-sensitively
# + return - `()` if no prohibited content is found, or an error describing the first violation
@EvalTemplate {
    label: "Content Safety",
    description: "Checks that agent responses contain none of the configured prohibited strings",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertContentSafety(ai:Agent targetAgent, ai:ConversationThread|string queries,
        string[] prohibitedStrings, boolean caseSensitive = false) returns Error? {
    if prohibitedStrings.length() == 0 {
        return error("[content-safety] no prohibited strings configured; add at least one prohibited string");
    }
    if queries is string {
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkProhibitedContent(userQuery = queries, actualResponse = actualResponse,
                prohibitedStrings = prohibitedStrings, caseSensitive = caseSensitive);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = queries.id);
        check checkProhibitedContent(userQuery = userQuery, actualResponse = actualResponse,
                prohibitedStrings = prohibitedStrings, caseSensitive = caseSensitive);
    }
}

# Checks that the expected response recorded in the eval set appears as a substring
# of the agent response, allowing the agent to elaborate around a canonical answer.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + caseSensitive - Whether the substring matching is case-sensitive. When `false`, only
# ASCII A–Z is folded, so non-ASCII letters still compare case-sensitively
# + return - `()` if every trace passes, or an error describing the first miss
@EvalTemplate {
    label: "Contains Match",
    description: "Checks that the expected response from the eval set appears as a substring of the agent response",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function assertContainsMatch(ai:Agent targetAgent, ai:ConversationThread thread,
        boolean caseSensitive = false) returns Error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check traceOutput(trace = expectedTrace);
        string expectedResponse = expectedOutput.content ?: "";
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = thread.id);
        string compareExpected = caseSensitive ? expectedResponse : expectedResponse.toLowerAscii();
        string compareActual = caseSensitive ? actualResponse : actualResponse.toLowerAscii();
        if !compareActual.includes(compareExpected) {
            return error(string `[contains-match] query "${userQuery}": expected response not found ` +
                    string `in agent response (actual length ${actualResponse.length()}, ` +
                    string `expected length ${expectedResponse.length()})`);
        }
    }
}

# Checks that the agent completes every run within the given number of iterations.
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + maxIterations - The maximum number of iterations allowed per agent run
# + return - `()` if every run stays within the limit, or an error describing the first excess
@EvalTemplate {
    label: "Iteration Efficiency",
    description: "Checks that the agent completes each run within the configured iteration limit",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertIterationEfficiency(ai:Agent targetAgent, ai:ConversationThread|string queries,
        int maxIterations = 5) returns Error? {
    if queries is string {
        ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkIterationCount(userQuery = queries, actualTrace = actualTrace,
                maxIterations = maxIterations);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = userQuery, sessionId = queries.id);
        check checkIterationCount(userQuery = userQuery, actualTrace = actualTrace,
                maxIterations = maxIterations);
    }
}

# Checks that the required strings all appear in the agent's output. For a thread,
# the check runs against the combined output of every trace, so each required string
# need only appear in one response. An empty required list is a configuration error
# and fails.
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + requiredStrings - The strings that must all appear in the agent output
# + caseSensitive - Whether the matching is case-sensitive. When `false`, only ASCII
# A–Z is folded, so non-ASCII letters still compare case-sensitively
# + return - `()` if every required string is found, or an error listing the missing ones
@EvalTemplate {
    label: "Content Coverage",
    description: "Checks that all required strings appear in the agent output",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertContentCoverage(ai:Agent targetAgent, ai:ConversationThread|string queries,
        string[] requiredStrings, boolean caseSensitive = false) returns Error? {
    if requiredStrings.length() == 0 {
        return error("[content-coverage] no required strings configured; add at least one required string");
    }
    string combinedResponses;
    if queries is string {
        combinedResponses = check getAgentResponse(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
    } else {
        string[] threadResponses = [];
        foreach ai:Trace expectedTrace in queries.traces {
            string userQuery = ai:getUserQuery(trace = expectedTrace);
            string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                    sessionId = queries.id);
            threadResponses.push(actualResponse);
        }
        combinedResponses = string:'join("\n", ...threadResponses);
    }
    string compareResponses = caseSensitive ? combinedResponses : combinedResponses.toLowerAscii();
    string[] missingStrings = [];
    foreach string requiredString in requiredStrings {
        string compareRequired = caseSensitive ? requiredString : requiredString.toLowerAscii();
        if !compareResponses.includes(compareRequired) {
            missingStrings.push(requiredString);
        }
    }
    if missingStrings.length() > 0 {
        return error(string `[content-coverage] ${missingStrings.length()}/${requiredStrings.length()} ` +
                string `required string(s) missing from the agent output: ` +
                string `"${string:'join("\", \"", ...missingStrings)}"`);
    }
}

# Checks that the agent produces every response within the given time limit.
#
# + targetAgent - The agent under evaluation
# + queries - The eval set conversation thread, or a single user query
# + maxLatencySeconds - The maximum time allowed per agent run, in seconds
# + return - `()` if every run finishes within the limit, or an error describing the first excess
@EvalTemplate {
    label: "Latency Performance",
    description: "Checks that the agent responds within the configured time limit",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function assertLatencyPerformance(ai:Agent targetAgent, ai:ConversationThread|string queries,
        decimal maxLatencySeconds = 10) returns Error? {
    if queries is string {
        ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = queries,
                sessionId = uuid:createType4AsString());
        return checkLatency(userQuery = queries, actualTrace = actualTrace,
                maxLatencySeconds = maxLatencySeconds);
    }
    foreach ai:Trace expectedTrace in queries.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = userQuery, sessionId = queries.id);
        check checkLatency(userQuery = userQuery, actualTrace = actualTrace,
                maxLatencySeconds = maxLatencySeconds);
    }
}

// ***** Shared helpers *****

// The `ballerina/ai` APIs fail with `ai:Error`, which is a distinct type and so not a
// subtype of this module's `Error`. Failures are converted at the boundary, keeping the
// original error as the cause, so every function in this module can report `Error`.

isolated function runAgent(ai:Agent targetAgent, string userQuery, string sessionId)
        returns ai:Trace|Error {
    ai:Trace|error actualTrace = targetAgent.run(query = userQuery, sessionId = sessionId);
    if actualTrace is error {
        return error(string `the agent failed to run the query "${userQuery}"`, actualTrace);
    }
    return actualTrace;
}

isolated function traceOutput(ai:Trace trace) returns ai:ChatAssistantMessage|Error {
    ai:ChatAssistantMessage|error output = trace.output;
    if output is error {
        return error("the trace carries no assistant output", output);
    }
    return output;
}

isolated function getAgentResponse(ai:Agent targetAgent, string userQuery, string sessionId)
        returns string|Error {
    ai:Trace actualTrace = check runAgent(targetAgent = targetAgent, userQuery = userQuery,
            sessionId = sessionId);
    return getResponseText(trace = actualTrace);
}

isolated function getResponseText(ai:Trace trace) returns string|Error {
    ai:ChatAssistantMessage output = check traceOutput(trace = trace);
    return output.content ?: "";
}

isolated function checkLength(string userQuery, string actualResponse, int minLength, int maxLength)
        returns Error? {
    int responseLength = actualResponse.length();
    if responseLength < minLength || responseLength > maxLength {
        return error(string `[length-compliance] query "${userQuery}": response length ` +
                string `${responseLength} is outside the range [${minLength}, ${maxLength}]`);
    }
}

isolated function checkProhibitedContent(string userQuery, string actualResponse, string[] prohibitedStrings,
        boolean caseSensitive) returns Error? {
    string compareResponse = caseSensitive ? actualResponse : actualResponse.toLowerAscii();
    string[] foundStrings = [];
    foreach string prohibitedString in prohibitedStrings {
        string compareProhibited = caseSensitive ? prohibitedString : prohibitedString.toLowerAscii();
        if compareResponse.includes(compareProhibited) {
            foundStrings.push(prohibitedString);
        }
    }
    if foundStrings.length() > 0 {
        return error(string `[content-safety] query "${userQuery}": response contains ` +
                string `${foundStrings.length()} prohibited string(s): ` +
                string `"${string:'join("\", \"", ...foundStrings)}"`);
    }
}

isolated function checkLatency(string userQuery, ai:Trace actualTrace, decimal maxLatencySeconds)
        returns Error? {
    decimal actualLatencySeconds = time:utcDiffSeconds(actualTrace.endTime, actualTrace.startTime);
    if actualLatencySeconds > maxLatencySeconds {
        return error(string `[latency-performance] query "${userQuery}": agent responded in ` +
                string `${actualLatencySeconds}s, exceeding the limit of ${maxLatencySeconds}s`);
    }
}

isolated function checkIterationCount(string userQuery, ai:Trace actualTrace, int maxIterations)
        returns Error? {
    int actualIterations = actualTrace.iterations.length();
    if actualIterations > maxIterations {
        return error(string `[iteration-efficiency] query "${userQuery}": agent used ` +
                string `${actualIterations} iterations, exceeding the limit of ${maxIterations}`);
    }
}

isolated function findFirstMismatch(string expectedResponse, string actualResponse) returns int {
    int comparableLength = int:min(expectedResponse.length(), actualResponse.length());
    foreach int charIndex in 0 ..< comparableLength {
        if expectedResponse[charIndex] != actualResponse[charIndex] {
            return charIndex;
        }
    }
    return comparableLength;
}

isolated function excerptAround(string text, int mismatchIndex) returns string {
    int windowStart = int:max(0, mismatchIndex - 20);
    int windowEnd = int:min(text.length(), mismatchIndex + 20);
    return text.substring(windowStart, windowEnd);
}

isolated function matchTrajectory(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls,
        TrajectoryMatchMode matchMode) returns boolean {
    match matchMode {
        STRICT => {
            return matchStrict(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        UNORDERED => {
            return matchUnordered(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        SUBSET => {
            return matchSubset(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
        SUPERSET => {
            return matchSuperset(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls);
        }
    }
    return false;
}

// `ai:FunctionCall.arguments` is nilable, so a call recorded with an explicit null
// and one carrying an empty map describe the same invocation. Normalize both to `{}`
// before comparing, matching what `describeToolCalls` renders.
isolated function callsMatch(ai:FunctionCall expectedCall, ai:FunctionCall actualCall) returns boolean =>
    expectedCall.name == actualCall.name &&
        (expectedCall.arguments ?: {}) == (actualCall.arguments ?: {});

isolated function matchStrict(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    foreach int callIndex in 0 ..< expectedToolCalls.length() {
        if !callsMatch(expectedCall = expectedToolCalls[callIndex], actualCall = actualToolCalls[callIndex]) {
            return false;
        }
    }
    return true;
}

isolated function matchUnordered(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    boolean[] matchedFlags = actualToolCalls.'map(actualCall => false);
    foreach ai:FunctionCall expectedCall in expectedToolCalls {
        boolean foundMatch = false;
        foreach int actualIndex in 0 ..< actualToolCalls.length() {
            if !matchedFlags[actualIndex]
                    && callsMatch(expectedCall = expectedCall, actualCall = actualToolCalls[actualIndex]) {
                matchedFlags[actualIndex] = true;
                foundMatch = true;
                break;
            }
        }
        if !foundMatch {
            return false;
        }
    }
    return true;
}

isolated function matchSubset(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    boolean[] matchedFlags = expectedToolCalls.'map(expectedCall => false);
    foreach ai:FunctionCall actualCall in actualToolCalls {
        boolean foundMatch = false;
        foreach int expectedIndex in 0 ..< expectedToolCalls.length() {
            if !matchedFlags[expectedIndex]
                    && callsMatch(expectedCall = expectedToolCalls[expectedIndex], actualCall = actualCall) {
                matchedFlags[expectedIndex] = true;
                foundMatch = true;
                break;
            }
        }
        if !foundMatch {
            return false;
        }
    }
    return true;
}

isolated function matchSuperset(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    boolean[] matchedFlags = actualToolCalls.'map(actualCall => false);
    foreach ai:FunctionCall expectedCall in expectedToolCalls {
        boolean foundMatch = false;
        foreach int actualIndex in 0 ..< actualToolCalls.length() {
            if !matchedFlags[actualIndex]
                    && callsMatch(expectedCall = expectedCall, actualCall = actualToolCalls[actualIndex]) {
                matchedFlags[actualIndex] = true;
                foundMatch = true;
                break;
            }
        }
        if !foundMatch {
            return false;
        }
    }
    return true;
}

isolated function describeToolCalls(ai:FunctionCall[] toolCalls) returns string {
    string[] callDescriptions = toolCalls.'map(toolCall =>
        string `${toolCall.name}(${(toolCall.arguments ?: {}).toJsonString()})`);
    return "[" + string:'join(", ", ...callDescriptions) + "]";
}
