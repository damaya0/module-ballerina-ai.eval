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

# The evaluation strategy a template uses to score agent behavior.
public enum EvalKind {
    # Scored deterministically by code (no LLM calls for scoring)
    RULE_BASED,
    # Scored by an LLM judge (requires a judge model, nondeterministic)
    LLM_JUDGE
}

# Metadata describing an evaluation template function. Read statically by tooling
# (Language Server / Integrator UI) to list, filter, and render the templates.
public type EvalTemplateConfig record {|
    # Human-readable name shown in the UI palette
    string label;
    # Short description of what the template checks
    string description?;
    # How the template scores the agent output
    EvalKind kind;
    # True if the template replays an eval set (recorded conversation threads);
    # false if it runs on ad hoc user queries
    boolean needsEvalset;
|};

# Marks a function as an evaluation template that low-code tooling can discover.
#
# Declared `const` so every attached value is a compile-time constant, letting the
# Language Server read the metadata from the syntax tree without executing code.
public const annotation EvalTemplateConfig EvalTemplate on function;
