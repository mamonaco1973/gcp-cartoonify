#GCP #Serverless #CloudFunctions #Firestore #Terraform #Python #IdentityPlatform #APIGateway

*Secure Serverless API on Google Cloud (Identity Platform + API Gateway)*

Deploy a fully authenticated serverless notes API on Google Cloud Platform using Terraform, Cloud Functions 2nd Gen, Firestore, and Cloud API Gateway. Users sign in via Identity Platform (Firebase Auth), and every API request is validated against a Firebase JWT before reaching the Cloud Function — with data scoped per user at the Firestore layer.

In this project we build a secure REST API with full Create, Read, Update, and Delete support — protected by real JWT authentication, deployed with a single script, and tested through a browser-based SPA with no server to manage.

WHAT YOU'LL LEARN
• Enabling GCP Identity Platform and configuring email/password sign-in via the REST API
• Issuing browser API keys scoped to identitytoolkit.googleapis.com with google_apikeys_key
• Defining a Cloud API Gateway with an OpenAPI spec that validates Firebase JWT tokens
• Forwarding decoded JWT claims to a private Cloud Function via X-Apigateway-Api-Userinfo
• Scoping Firestore reads and writes to the authenticated user's UID (sub claim)
• Hosting a static SPA on a public GCS bucket with runtime config loaded from config.json

INFRASTRUCTURE DEPLOYED
• Cloud Function (2nd Gen, Python 3.11, HTTP trigger, private — invoked only by gateway SA)
• Cloud API Gateway with OpenAPI 2.0 spec (Firebase JWT securityDefinitions)
• Identity Platform (email/password sign-in, Firebase JS SDK)
• GCS bucket for function source code (zip archive, content-addressed)
• Firestore database (Native mode, us-central1)
• Service accounts: notes-sa (Firestore), notes-gateway-sa (Cloud Run invoker)
• GCS bucket hosting a static web frontend

GitHub
https://github.com/mamonaco1973/gcp-identity-app

README
https://github.com/mamonaco1973/gcp-identity-app/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:15 Architecture
00:40 Build the Code
00:56 Build Results
01:39 Demo
