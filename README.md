# Ballerina AI Evaluation Library

[![Build](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/build-timestamped-master.yml)
[![codecov](https://codecov.io/gh/ballerina-platform/module-ballerina-ai.eval/branch/main/graph/badge.svg)](https://codecov.io/gh/ballerina-platform/module-ballerina-ai.eval)
[![Trivy](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/trivy-scan.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/trivy-scan.yml)
[![GraalVM Check](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerina-ai.eval/actions/workflows/build-with-bal-test-graalvm.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerina-ai.eval.svg)](https://github.com/ballerina-platform/module-ballerina-ai.eval/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/ai.eval.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%2Fai.eval)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Evaluation templates for AI agents built with the `ballerina/ai` module: rule-based templates scored
in code, and LLM-as-a-judge templates scored by a judge model. Each template returns an `error` on
failure, so evaluations run as ordinary Ballerina tests.

See the [module documentation](./ballerina/README.md) for the template list and usage.

## Issues and projects

Issues and Projects tabs are disabled for this repository as this is part of the Ballerina Library. To report bugs, request new features, start new discussions, view project boards, etc., go to the [Ballerina Library parent repository](https://github.com/ballerina-platform/ballerina-library).

This repository only contains the source code for the package.

## Build from the source

### Set Up the prerequisites

1. Download and install the Java SE Development Kit (JDK) version 21.

   * [OpenJDK](https://adoptium.net/)

        > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Generate a GitHub access token with read package permissions, then set the following environment
   variables. Replace the placeholders with your own values before running the commands.

```shell
export packageUser="<Your GitHub username>"
export packagePAT="<GitHub personal access token>"
```

### Build the source

Execute the commands below to build from source.

1. To build the library:

```bash
./gradlew clean build
```

2. To run the tests:

```bash
./gradlew clean test
```

3. To run a group of tests:

```bash
./gradlew clean test -Pgroups=<test_group_names>
```

4. To build the package without the tests:

```bash
./gradlew clean build -x test
```

5. To debug the tests:

```bash
./gradlew clean test -Pdebug=<port>
```

6. To debug with Ballerina language:

```bash
./gradlew clean build -PbalJavaDebug=<port>
```

7. Publish the generated artifacts to the local Ballerina central repository:

```bash
./gradlew clean build -PpublishToLocalCentral=true
```

8. Publish the generated artifacts to the Ballerina central repository:

```bash
./gradlew clean build -PpublishToCentral=true
```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).
