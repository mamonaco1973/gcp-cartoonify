#GCP #Serverless #CloudFunctions #VertexAI #PubSub #Firestore #APIGateway #IdentityPlatform #Terraform #Python #GenerativeAI

*Build an AI Image Pipeline on GCP (Vertex + Cloud Functions + Pub/Sub)*

Turn any photo into a cartoon using a fully serverless, event-driven pipeline on GCP — provisioned with Terraform and deployed with a single script. Users sign in with Firebase email/password (Identity Platform), upload a photo, pick a cartoon style, and a Pub/Sub-driven worker invokes Vertex AI Imagen with subject-reference prompting to generate a stylized portrait. Originals and cartoons are stored privately in GCS and served through short-lived V4 signed URLs.

In this project we build an asynchronous AI image-processing pipeline from scratch — the browser uploads directly to GCS via a V4 signed PUT URL, Pub/Sub decouples the slow Imagen inference call from the API response, and a Cloud Function running Pillow normalizes the photo before sending it to Vertex AI. The whole thing runs without a single VM.

WHAT YOU'LL LEARN
• Invoking Vertex AI Imagen (imagen-3.0-capability-001) with SubjectReferenceImage for person likeness preservation
• Using Pub/Sub + Eventarc to decouple a slow AI inference call from a synchronous API response
• Consolidating multiple API routes into a single Cloud Function with internal path routing
• Implementing Firebase email/password auth (Identity Platform) in a static SPA
• Attaching a JWT authorizer to API Gateway (validating Firebase ID tokens)
• Generating V4 signed PUT URLs for direct browser-to-GCS upload
• Enforcing per-user daily quotas with a Firestore range query
• Managing Firestore composite indexes outside Terraform to avoid async lifecycle conflicts

INFRASTRUCTURE DEPLOYED
• Identity Platform (Firebase Auth) with email/password sign-in
• API Gateway with Firebase JWT authorizer (validates against Identity Platform JWKS)
• Single zip-packaged API Cloud Function (Python 3.12): upload-url, generate, result, history, delete
• Worker Cloud Function (512 MB, 300 s timeout) triggered by Pub/Sub via Eventarc
• Pub/Sub topic (cartoonify-jobs) with dead-letter policy
• Firestore (Native mode) with composite indexes for history and quota queries
• GCS web bucket (public SPA hosting) + GCS media bucket (private, 7-day lifecycle)
• IAM service accounts scoped per function — API role cannot invoke Vertex AI; worker role cannot delete

GitHub
https://github.com/mamonaco1973/gcp-cartoonify

README
https://github.com/mamonaco1973/gcp-cartoonify/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:14 Architecture
00:49 Build the Code
01:04 Build Results
01:48 Demo
