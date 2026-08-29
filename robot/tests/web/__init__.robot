*** Settings ***
Documentation       Browser-driven UI suites.
...
...                 Suite setup here runs once for the whole ``tests/web``
...                 directory: fixtures up, one browser launched. Each test then
...                 gets its own context and page via `Open Login Page`.

Resource            ../../resources/web.resource

Suite Setup         Run Keywords    Start Test Fixtures    AND    Open Browser For Suite
Suite Teardown      Run Keywords    Close Browser For Suite    AND    Stop Test Fixtures

Test Tags           web
