# Video Script — Serverless CRUD API on GCP with Cloud Functions and Firestore

---

## Introduction

[ Opening Sequence ]

“Do you want to build an AI-powered image pipeline on Google Cloud?”

[ Show Diagram ]

"In this project, we build a fully serverless pipeline that turns photos into cartoons using Google Cloud and Vertex."

[ Build B Roll ]

Follow along and in minutes you’ll have a fully working AI pipeline running on Google Cloud.

---

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Diagram then Congito ]

"First, the user signs into the web application using Google's Identity Platform.

[ Choose File then Diagam ]

"When the user selects “Choose File”, the image is uploaded to the media bucket."

[  Cartoonify ]

When the user selects “Cartoonify”, the API does two things:

[ Highlight Firebase]

It creates a job record in Firebase.

[ Highlight Pub/Sub queue ]

Then it sends a message to the image processing Pub-Sub topic.

[ Highlight Lambda ]

"Pub-Sub triggers the worker cloud function."

[ Show bedrock ]

"The worker calls Vertex to generate the cartoon."

[ Show S3 Media Bucket]

"The generated image is written back to media bucket.

[ Final Firebase State]

When processing completes, the job status is updated in Firebase.

[ Show final result ]

The web application refreshes and displays the generated image.
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

Navigate to the web application URL

Sign in using the Identity Platform.

Select “Choose File” and upload a test image.

Select the “Pixar 3D” style, then click “Cartoonify” to start the image generation pipeline.

The application displays the image generation lifecycle in the left hand panel.

When processing completes, the application refreshes and shows the result.

Now try some different styles.

The application displays a gallery of your previous results.