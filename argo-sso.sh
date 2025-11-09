#!/bin/bash

# ===================================================================
# 1. EDIT THESE VALUES
# ===================================================================
# Paste your Google Client ID and Secret here
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
# ===================================================================

set -e

echo "--- 1. Patching 'argocd-secret' with your Google credentials ---"
# Base64 encode the secrets for Kubernetes
CLIENT_ID_B64=$(printf '%s' "$GOOGLE_CLIENT_ID" | base64 | tr -d '\n')
CLIENT_SECRET_B64=$(printf '%s' "$GOOGLE_CLIENT_SECRET" | base64 | tr -d '\n')


kubectl patch secret argocd-secret \
  -n argocd \
  -p '{"data": {"dex.google.clientID": "'$CLIENT_ID_B64'", "dex.google.clientSecret": "'$CLIENT_SECRET_B64'"}}'

echo "--- 2. Patching 'argocd-cm' to enable and configure Dex ---"
# This patches the two keys (oidc.config and dex.config) into the main ConfigMap
kubectl patch configmap argocd-cm \
  -n argocd \
  --type merge \
  -p '
data:
  
  url: https://argocd.trivoconnect.com
  oidc.config: |
    name: Google
    issuer: https://argocd.trivoconnect.com/api/dex
    clientID: $GOOGLE_CLIENT_ID
    clientSecret: $GOOGLE_CLIENT_SECRET
    requestedScopes: ["openid", "profile", "email", "groups"]


  dex.config: |
    connectors:
    - type: google
      id: google
      name: Google
      config:
        baseURL: https://argocd.trivoconnect.com/api/dex
        clientID: $GOOGLE_CLIENT_ID
        clientSecret: $GOOGLE_CLIENT_SECRET
        scopes:
        - openid
        - email
        - profile
        - groups
        redirectURI: https://argocd.trivoconnect.com/api/dex/callback
'

echo "--- 3. Patching 'argocd-rbac-cm' to grant Admin roles ---"
# This adds your user and group as admins
kubectl patch configmap argocd-rbac-cm \
  -n argocd \
  --type merge \
  -p '
data:
  policy.g: |
    g, nitesh@trivoconnect.com, role:admin
    g, grafana@trivoconnect.com, role:admin
'

echo "--- 4. Patching 'argocd-dex-server' to load the secret ---"
# This is the critical step that injects the secret as environment variables
kubectl patch deployment argocd-dex-server \
  -n argocd \
  --type=strategic \
  -p '
spec:
  template:
    spec:
      containers:
      - name: dex
        envFrom:
        - secretRef:
            name: argocd-secret
'

echo "--- 5. Patching 'argocd-server' to load the secret ---"
# This is also critical, so the UI can read the clientID
kubectl patch deployment argocd-server \
  -n argocd \
  --type=strategic \
  -p '
spec:
  template:
    spec:
      containers:
      - name: argocd-server
        envFrom:
        - secretRef:
            name: argocd-secret
'

echo "--- 6. Restarting pods to load new configuration ---"
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd

echo "All done! Please wait 1-2 minutes for the pods to restart."