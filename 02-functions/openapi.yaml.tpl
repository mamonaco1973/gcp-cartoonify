swagger: "2.0"
info:
  title: cartoonify-api
  version: "1.0"
host: "placeholder.example.com"
schemes:
  - https
produces:
  - application/json

# Each path has its own x-google-backend pointing to a dedicated function.
# OPTIONS operations have no security requirement — CORS preflight passes freely.

paths:
  /upload-url:
    options:
      operationId: corsUploadUrl
      x-google-backend:
        address: ${upload_url_uri}
        jwt_audience: ${upload_url_uri}
        protocol: h2
      responses:
        "204":
          description: CORS preflight
    post:
      operationId: uploadUrl
      security:
        - firebase: []
      x-google-backend:
        address: ${upload_url_uri}
        jwt_audience: ${upload_url_uri}
        protocol: h2
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
      x-google-backend:
        address: ${submit_uri}
        jwt_audience: ${submit_uri}
        protocol: h2
      responses:
        "204":
          description: CORS preflight
    post:
      operationId: generate
      security:
        - firebase: []
      x-google-backend:
        address: ${submit_uri}
        jwt_audience: ${submit_uri}
        protocol: h2
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
      x-google-backend:
        address: ${result_uri}
        jwt_audience: ${result_uri}
        protocol: h2
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
      x-google-backend:
        address: ${result_uri}
        jwt_audience: ${result_uri}
        protocol: h2
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
      x-google-backend:
        address: ${history_uri}
        jwt_audience: ${history_uri}
        protocol: h2
      responses:
        "204":
          description: CORS preflight
    get:
      operationId: getHistory
      security:
        - firebase: []
      x-google-backend:
        address: ${history_uri}
        jwt_audience: ${history_uri}
        protocol: h2
      responses:
        "200":
          description: Newest 50 jobs for the authenticated user

  /history/{job_id}:
    options:
      operationId: corsHistoryId
      x-google-backend:
        address: ${delete_uri}
        jwt_audience: ${delete_uri}
        protocol: h2
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
      x-google-backend:
        address: ${delete_uri}
        jwt_audience: ${delete_uri}
        protocol: h2
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
