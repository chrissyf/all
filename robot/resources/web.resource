*** Settings ***
Documentation       Browser (Playwright) setup and page keywords for ``tests/web``.
...
...                 Suites should talk to this file, not to the Browser library
...                 directly - keeping selectors in one place means a markup
...                 change is a one-line fix here instead of an edit per suite.

Resource            ${CURDIR}/common.resource
Library             Browser    timeout=${BROWSER_TIMEOUT}


*** Variables ***
${BROWSER}                  chromium
${HEADLESS}                 ${True}
${BROWSER_TIMEOUT}          10s

# Point Playwright at a browser binary that is already on the machine, instead
# of the one `rfbrowser init` downloads. Handy on CI images that ship Chromium:
#    robot --variable BROWSER_EXECUTABLE:/opt/pw-browsers/chromium tests/web
${BROWSER_EXECUTABLE}       ${EMPTY}

# Selectors live here, one variable per element. Prefer a stable hook - an id or
# a data-testid - over a CSS path that breaks the next time the page is styled.
${LOGIN_USERNAME}           id=username
${LOGIN_PASSWORD}           id=password
${LOGIN_SUBMIT}             id=login-button
${LOGIN_ERROR}              id=login-error
${WELCOME_BANNER}           id=welcome-banner
${USER_TABLE}               id=user-table


*** Keywords ***
Open Browser For Suite
    [Documentation]    Launch one browser process for the whole run. Contexts and
    ...    pages are per test, so tests stay isolated without paying the
    ...    browser startup cost each time.
    IF    $BROWSER_EXECUTABLE
        New Browser
        ...    ${BROWSER}
        ...    headless=${HEADLESS}
        ...    executablePath=${BROWSER_EXECUTABLE}
    ELSE
        New Browser    ${BROWSER}    headless=${HEADLESS}
    END

Close Browser For Suite
    [Documentation]    Close every browser this run opened.
    Close Browser    ALL

Open Login Page
    [Documentation]    Start a test on a clean context, so cookies and local
    ...    storage never leak between tests.
    New Context    viewport={'width': 1280, 'height': 720}
    New Page    ${BASE_URL}/login

Sign In As
    [Documentation]    Fill the login form and submit it.
    [Arguments]    ${username}    ${password}
    Fill Text    ${LOGIN_USERNAME}    ${username}
    Fill Text    ${LOGIN_PASSWORD}    ${password}
    Click    ${LOGIN_SUBMIT}

Dashboard Should Greet
    [Documentation]    Assert the dashboard loaded and greets the given user.
    [Arguments]    ${username}
    Wait For Elements State    ${WELCOME_BANNER}    visible
    Get Text    ${WELCOME_BANNER}    ==    Welcome, ${username}!

Login Error Should Be Shown
    [Documentation]    Assert the form rejected the attempt and said so.
    [Arguments]    ${message}=Invalid credentials.
    Wait For Elements State    ${LOGIN_ERROR}    visible
    Get Text    ${LOGIN_ERROR}    ==    ${message}
