*** Settings ***
Documentation       HTTP API suites.
...
...                 Suite setup here runs once for the whole ``tests/api``
...                 directory: fixtures up, one authenticated session created.

Resource            ../../resources/api.resource

Suite Setup         Run Keywords    Start Test Fixtures    AND    Create API Session
Suite Teardown      Run Keywords    Delete API Session    AND    Stop Test Fixtures

Test Tags           api
