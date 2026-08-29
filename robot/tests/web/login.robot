*** Settings ***
Documentation       Sign-in flow: the happy path, a rejected attempt, and the
...                 state of the page a user first lands on.

Resource            ../../resources/web.resource

Test Setup          Open Login Page


*** Test Cases ***
Valid Credentials Sign The User In
    [Documentation]    A correct username and password land on the dashboard.
    [Tags]    smoke
    Sign In As    ${USERNAME}    ${PASSWORD}
    Dashboard Should Greet    ${USERNAME}

Wrong Password Is Rejected
    [Documentation]    A bad password keeps the user on the login form and shows
    ...    an error, rather than silently doing nothing.
    Sign In As    ${USERNAME}    not-the-password
    Login Error Should Be Shown
    Get Url    *=    /login

Login Page Shows The Sign In Form
    [Documentation]    The form and its fields are present before any input.
    [Tags]    smoke
    Get Title    ==    Scaffold - Sign in
    Wait For Elements State    ${LOGIN_USERNAME}    visible
    Wait For Elements State    ${LOGIN_PASSWORD}    visible
    Get Text    ${LOGIN_SUBMIT}    ==    Sign in
