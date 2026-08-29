*** Settings ***
Documentation       The page behind the login, reached through the UI rather than
...                 by navigating straight to its URL - the test should exercise
...                 the same path a user takes.

Resource            ../../resources/web.resource

Test Setup          Sign In Through The Login Page


*** Test Cases ***
Dashboard Lists The Seeded Users
    [Documentation]    Every user the API knows about shows up in the table.
    ${rows} =    Get Element Count    ${USER_TABLE} >> tbody >> tr
    Should Be True    ${rows} > 0    The user table rendered no rows

Dashboard Offers A Way Out
    [Documentation]    The sign-out link is present and points back to login.
    Get Attribute    id=logout-link    href    *=    /login


*** Keywords ***
Sign In Through The Login Page
    [Documentation]    Test setup: open a fresh page and log in.
    Open Login Page
    Sign In As    ${USERNAME}    ${PASSWORD}
    Dashboard Should Greet    ${USERNAME}
