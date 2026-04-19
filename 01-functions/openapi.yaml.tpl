swagger: "2.0"
info:
  title: notes-api
  version: "1.0"
host: "placeholder.example.com"
schemes:
  - https
produces:
  - application/json

# All requests are forwarded to the Cloud Run service URI.
# APPEND_PATH_TO_ADDRESS (default) appends the request path, so:
#   GET /notes       → ${function_uri}/notes     → request.path = "/notes"
#   GET /notes/{id}  → ${function_uri}/notes/{id} → request.path = "/notes/{id}"
x-google-backend:
  address: ${function_uri}
  jwt_audience: ${function_uri}
  protocol: h2

paths:
  /notes:
    # OPTIONS passes through without auth for CORS preflight.
    options:
      operationId: corsNotes
      responses:
        "204":
          description: CORS preflight
    get:
      operationId: listNotes
      security:
        - firebase: []
      responses:
        "200":
          description: List of notes
    post:
      operationId: createNote
      security:
        - firebase: []
      parameters:
        - in: body
          name: body
          schema:
            type: object
      responses:
        "201":
          description: Created note

  /notes/{id}:
    options:
      operationId: corsNotesId
      parameters:
        - in: path
          name: id
          required: true
          type: string
      responses:
        "204":
          description: CORS preflight
    get:
      operationId: getNote
      security:
        - firebase: []
      parameters:
        - in: path
          name: id
          required: true
          type: string
      responses:
        "200":
          description: Note
    put:
      operationId: updateNote
      security:
        - firebase: []
      parameters:
        - in: path
          name: id
          required: true
          type: string
        - in: body
          name: body
          schema:
            type: object
      responses:
        "200":
          description: Updated note
    delete:
      operationId: deleteNote
      security:
        - firebase: []
      parameters:
        - in: path
          name: id
          required: true
          type: string
      responses:
        "200":
          description: Deleted

securityDefinitions:
  firebase:
    authorizationUrl: ""
    flow: implicit
    type: oauth2
    x-google-issuer: "https://securetoken.google.com/${project_id}"
    x-google-jwks_uri: "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
    x-google-audiences: "${project_id}"
