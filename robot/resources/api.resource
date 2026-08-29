*** Settings ***
Documentation       HTTP session handling and request keywords for ``tests/api``.
...
...                 One authenticated session is created per suite and reused by
...                 every test, which keeps connection setup out of the tests.

Resource            ${CURDIR}/common.resource
Library             Collections
Library             RequestsLibrary


*** Variables ***
${API_SESSION}          scaffold-api
${USERS_ENDPOINT}       /api/users
${HEALTH_ENDPOINT}      /api/health


*** Keywords ***
Create API Session
    [Documentation]    Open a session against ``${BASE_URL}`` carrying the bearer
    ...    token, so individual requests do not have to repeat auth headers.
    VAR    &{headers} =
    ...    Authorization=Bearer ${API_TOKEN}
    ...    Content-Type=application/json
    Create Session    ${API_SESSION}    ${BASE_URL}    headers=${headers}

Delete API Session
    [Documentation]    Close the sessions this run opened.
    Delete All Sessions

Get Health
    [Documentation]    GET the health endpoint and return the response.
    ${response} =    GET On Session    ${API_SESSION}    ${HEALTH_ENDPOINT}
    RETURN    ${response}

List Users
    [Documentation]    GET the user collection and return the response.
    ${response} =    GET On Session    ${API_SESSION}    ${USERS_ENDPOINT}
    RETURN    ${response}

Get User
    [Documentation]    GET a single user. Pass ``expected_status`` to assert on a
    ...    failure response instead of raising, e.g. ``expected_status=404``.
    [Arguments]    ${user_id}    ${expected_status}=200
    ${response} =    GET On Session
    ...    ${API_SESSION}
    ...    ${USERS_ENDPOINT}/${user_id}
    ...    expected_status=${expected_status}
    RETURN    ${response}

Create User
    [Documentation]    POST a new user. ``${payload}`` is a dictionary, typically
    ...    built with the `New User Payload` keyword from ``DataFactory.py``.
    [Arguments]    ${payload}    ${expected_status}=201
    ${response} =    POST On Session
    ...    ${API_SESSION}
    ...    ${USERS_ENDPOINT}
    ...    json=${payload}
    ...    expected_status=${expected_status}
    RETURN    ${response}

Delete User
    [Documentation]    DELETE a user by id.
    [Arguments]    ${user_id}    ${expected_status}=204
    ${response} =    DELETE On Session
    ...    ${API_SESSION}
    ...    ${USERS_ENDPOINT}/${user_id}
    ...    expected_status=${expected_status}
    RETURN    ${response}

Response Body Should Contain Keys
    [Documentation]    Assert the JSON body is an object holding every given key.
    [Arguments]    ${response}    @{keys}
    VAR    ${body} =    ${response.json()}
    FOR    ${key}    IN    @{keys}
        Dictionary Should Contain Key    ${body}    ${key}
        ...    msg=Response body is missing the '${key}' key: ${body}
    END
    RETURN    ${body}
