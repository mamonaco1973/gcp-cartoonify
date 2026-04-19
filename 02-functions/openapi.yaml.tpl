swagger: "2.0"
info:
  title: cartoonify-api
  version: "1.0"
host: "placeholder.example.com"
schemes:
  - https
produces:
  - application/json

# Single global backend routes all paths to the cartoonify_api function.
# OPTIONS operations have no security requirement — CORS preflight passes freely.
x-google-backend:
  address: ${function_uri}
  jwt_audience: ${function_uri}
  protocol: h2

paths:
  /upload-url:
    options:
      operationId: corsUploadUrl
      responses:
        "204":
          description: CORS preflight
    post:
      operationId: uploadUrl
      security:
        - firebase: []
      parameters:
        - in: body
          name: body
          schema:
            type: object
      responses:
        "200":
          description: Presigned upload URL

  /generate:
    options:
      operationId: corsGenerate
      responses:
        "204":
          description: CORS preflight
    post:
      operationId: generate
      security:
        - firebase: []
      parameters:
        - in: body
          name: body
          schema:
            type: object
      responses:
        "202":
          description: Job submitted

  /result/{job_id}:
    options:
      operationId: corsResult
      parameters:
        - in: path
          name: job_id
          required: true
          type: string
      responses:
        "204":
          description: CORS preflight
    get:
      operationId: getResult
      security:
        - firebase: []
      parameters:
        - in: path
          name: job_id
          required: true
          type: string
      responses:
        "200":
          description: Job status and presigned URLs

  /history:
    options:
      operationId: corsHistory
      responses:
        "204":
          description: CORS preflight
    get:
      operationId: getHistory
      security:
        - firebase: []
      responses:
        "200":
          description: Newest 50 jobs for the authenticated user

  /history/{job_id}:
    options:
      operationId: corsHistoryId
      parameters:
        - in: path
          name: job_id
          required: true
          type: string
      responses:
        "204":
          description: CORS preflight
    delete:
      operationId: deleteJob
      security:
        - firebase: []
      parameters:
        - in: path
          name: job_id
          required: true
          type: string
      responses:
        "200":
          description: Job deleted

securityDefinitions:
  firebase:
    authorizationUrl: ""
    flow: implicit
    type: oauth2
    x-google-issuer: "https://securetoken.google.com/${project_id}"
    x-google-jwks_uri: "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
    x-google-audiences: "${project_id}"
