# module-ballerina-ai.eval

A collection of evaluation templates, and prompts for AI agent evaluation.

This is the library module for evaluating AI agents built with the `ballerina/ai` module. It provides
rule-based evaluation templates, scored deterministically in code, and LLM-as-a-judge templates,
scored by a judge model. Each template runs the agent and returns an `error` on failure, so
evaluations plug directly into Ballerina test functions.

For the list of available templates and usage examples, see the [module documentation](./ballerina/README.md).

## Issues and projects

Issues and Projects tabs are disabled for this repository as this is part of the Ballerina Standard Library. To report bugs, request new features, start new discussions, view project boards, etc. please visit Ballerina Standard Library [parent repository](https://github.com/ballerina-platform/ballerina-standard-library).

This repository only contains the source code for the package.

## Build from the source

### Set Up the prerequisites

1. Download and install the Java SE Development Kit (JDK) version 21.

   * [OpenJDK](https://adoptium.net/)

        > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Export GitHub Personal access token with read package permissions as follows,

        export packageUser=<Username>
        export packagePAT=<Personal access token>

### Build the source

Execute the commands below to build from source.

1. To build the library:

    ```
    ./gradlew clean build
    ```

2. To run the tests:

    ```
    ./gradlew clean test
    ```

3. To run a group of tests

    ```
    ./gradlew clean test -Pgroups=<test_group_names>
    ```

4. To build the package without the tests:

    ```
    ./gradlew clean build -x test
    ```

5. To debug the tests:

    ```
    ./gradlew clean test -Pdebug=<port>
    ```

6. To debug with Ballerina language:

    ```
    ./gradlew clean build -PbalJavaDebug=<port>
    ```

7. Publish the generated artifacts to the local Ballerina central repository:

    ```
    ./gradlew clean build -PpublishToLocalCentral=true
    ```

8. Publish the generated artifacts to the Ballerina central repository:

    ```
    ./gradlew clean build -PpublishToCentral=true
    ```

## Contribute to Ballerina

As an open source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).
