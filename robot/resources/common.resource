*** Settings ***
Documentation       Shared configuration and the fixture lifecycle.
...
...                 Imported by both ``web.resource`` and ``api.resource``, so
...                 anything defined here is available to every suite.

Library             ${CURDIR}/../libraries/FixtureServer.py
Library             ${CURDIR}/../libraries/DataFactory.py


*** Variables ***
# Base URL of a real deployment, e.g.
#    robot --variable TARGET_URL:https://staging.example.com tests
# Left empty, the bundled fixture server is started instead.
${TARGET_URL}       ${EMPTY}

# Bearer token for the API suites. Filled in automatically when the fixture
# server is used; pass it on the command line for a real target.
${API_TOKEN}        ${EMPTY}

${USERNAME}         demo
${PASSWORD}         s3cret

# Resolved by `Start Test Fixtures`. Read this from suites; never read
# ${TARGET_URL} directly.
${BASE_URL}         ${EMPTY}


*** Keywords ***
Start Test Fixtures
    [Documentation]    Resolve ``${BASE_URL}`` and, when no external target was
    ...    given, boot the bundled fixture server with a clean data set.
    ...
    ...    Safe to call from several suite setups in one run: the server is a
    ...    global-scope library that hands back the already running instance.
    # robocop: off=VAR04 - the fixture server binds an ephemeral port, so the
    # base URL genuinely cannot be known until the run has started.
    IF    $TARGET_URL
        VAR    ${BASE_URL} =    ${TARGET_URL}    scope=GLOBAL
        Log    Testing external target ${TARGET_URL}    level=INFO
    ELSE
        ${url} =    Start Fixture Server
        Reset Fixture Data
        ${token} =    Fixture Api Token
        VAR    ${BASE_URL} =    ${url}    scope=GLOBAL
        VAR    ${API_TOKEN} =    ${token}    scope=GLOBAL
        Log    Started bundled fixture server at ${url}    level=INFO
    END

Stop Test Fixtures
    [Documentation]    Shut the fixture server down. Does nothing when the run
    ...    targets an external deployment, since we did not start anything.
    IF    not $TARGET_URL    Stop Fixture Server
