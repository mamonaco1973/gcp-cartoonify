# Video Script — Serverless CRUD API on GCP with Cloud Functions and Firestore

---

## Introduction

[ Show web application log in ]

Do you need a secure, serverless API on Google Cloud?

[ Architecture diagram — walk through it left to right: browser, Cloud Storage, Cloud Function, Firestore ]

In this project, we build a secure notes API using Cloud Functions, Firestore, API Gateway, and Google's Identity Platform.

[Terminal running apply.sh — Terraform output flying by, ending with the website URL ]

Follow along and in minutes you'll have a secured serverless API running in Google Cloud.

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Highlight Browser + Identity Platform ]

“The user signs in with Identity Platform, and the browser receives a bearer token for API calls”

[ Highlight Browser to Gateway ]

“That token goes with each call to the API Gateway.”

[ Highlight Gateway ]

“The gateway validates the token before calling the Cloud Functions.

[ Highlight Cloud Function ]

“The Cloud Functions are the API compute layer and are implemented in Python.


[ Highlight Firestore ]

"Firestore stores the notes data, isolated per user.”

---

## Build the Code

[ Terminal — running ./apply.sh ]

"The whole deployment is one script — apply.sh. Two phases."

[ Terminal — check_env.sh running, API enablement output ]

"First, check_env.sh validates your tools, authenticates gcloud, enables the required GCP APIs, and creates the Firestore database in native mode."

[ Terminal — Phase 1: Terraform apply in 01-functions ]

"Phase one: Terraform provisions the Cloud Function and its supporting infrastructure — a service account scoped to Firestore, a GCS bucket to hold the source zip, and the function itself wired to that bucket."

[ Terminal — Phase 2: envsubst then Terraform apply in 02-webapp ]

"Phase two: envsubst injects the Cloud Function base URL into the HTML template. Terraform creates a public Cloud Storage bucket and uploads the generated index.html — the site is live."

[ Terminal — deployment complete, URLs printed ]

"Function URL. Website URL. Done."

---

## Build Results

[ Identity Platform Users]

"First is the Identity Platform. This is where user accounts are managed"

[ Identify Platform Main ]

A simple email and password provider is used for this application.

[ Identify Platfom Other Providers]

Additional third-party identity providers can be configured as needed.

[ GCP Console — API Keys ]

"The browser API key is scoped to Identity Platform and is used in the web application."

[ GCP Console — API Gateway ]

"Next is API Gateway."

[ Show Security Definition / Auth Section ]

"The JWT validation is configured here."

[ Show API call ]

"API Gateway validates the caller's Bearer token before calling the Cloud Function."

[ GCP Console — Cloud Functions, notes ]

"The Cloud Functions are implemented in Python and handles all five routes."

[ GCP Console — Firestore, notes collection ]

"Firestore stores the notes — scoped to the authenticated user by the owner field.
Firestore stores the notes, scoped to the authenticated user by the owner field

[ GCP Console — Cloud Storage, web bucket ]

"Finally, a public Cloud Storage bucket hosts the static web application."

[ Browser — Notes Demo loads ]

"Navigate to the URL to launch the test application."

---

## Demo

[ Browser — Notes Demo, open DevTools → Network tab ]

"When the application loads we are prompted to login."

[ Sign In ]

Sign in with an existing account — or create one here.

[ Show redirect link ]

The Identity Platform re-directs back to callback.html. The page exchanges the authorization code for tokens.

[ Show initial state ]

We're now authenticated into the app. Open the browser debugger so we can watch the API calls.

[  Create a new note ]

Create a new note.

[ Show create API call with bearer token ]

"A POST is made with the JWT as a Bearer token."

[ Editing and clicking Save ]

"Now update the note."

[ Show network tab ]

"The PUT call is made with the Bearer token set."

[ Delete prompt ]

"Delete the Note".

[ Show network tab ]

'The DELETE call is made with the Bearer token set."

[ Browser — empty list ]

"In this demo we've exercised every API endpoint — all secured with JWT bearer tokens."

---
