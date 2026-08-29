*** Settings ***
Documentation       The ``/api/users`` collection: reading, creating, deleting,
...                 and the error responses each of those can produce.

Resource            ../../resources/api.resource


*** Test Cases ***
Health Endpoint Reports OK
    [Documentation]    The cheapest possible check that the target is up.
    [Tags]    smoke
    ${response} =    Get Health
    Status Should Be    200    ${response}
    Should Be Equal    ${response.json()}[status]    ok

Listing Users Returns The Collection
    [Documentation]    The list endpoint returns users and a matching count.
    [Tags]    smoke
    ${response} =    List Users
    ${body} =    Response Body Should Contain Keys    ${response}    users    count
    Length Should Be    ${body}[users]    ${body}[count]
    Should Not Be Empty    ${body}[users]

Creating A User Returns The Created Resource
    [Documentation]    POST echoes back the stored user, with a server-assigned
    ...    id, and the user is then retrievable.
    ${payload} =    New User Payload
    ${response} =    Create User    ${payload}
    ${created} =    Response Body Should Contain Keys    ${response}    id    name    email
    Should Be Equal    ${created}[name]    ${payload}[name]
    Should Be Equal    ${created}[email]    ${payload}[email]

    ${fetched} =    Get User    ${created}[id]
    Should Be Equal    ${fetched.json()}    ${created}

Deleting A User Removes It
    [Documentation]    DELETE returns 204 and the user is gone afterwards.
    ${created} =    Create User    ${{ {'name': 'Temp User', 'email': 'temp@example.com'} }}
    VAR    ${user_id} =    ${created.json()}[id]

    Delete User    ${user_id}
    Get User    ${user_id}    expected_status=404

Creating A User Without An Email Is Rejected
    [Documentation]    Validation failures come back as 400 with a reason.
    ${payload} =    New User Payload    email=${EMPTY}
    ${response} =    Create User    ${payload}    expected_status=400
    Should Contain    ${response.json()}[error]    email

Requesting A Missing User Returns 404
    [Documentation]    An unknown id is a 404, not a 500 or an empty 200.
    ${response} =    Get User    999999    expected_status=404
    Should Be Equal    ${response.json()}[error]    User not found

Unauthenticated Requests Are Rejected
    [Documentation]    Without the bearer token the collection is off limits.
    ...    Uses its own session, leaving the suite's authenticated one intact.
    Create Session    anonymous    ${BASE_URL}
    ${response} =    GET On Session    anonymous    ${USERS_ENDPOINT}    expected_status=401
    Should Contain    ${response.json()}[error]    bearer token
