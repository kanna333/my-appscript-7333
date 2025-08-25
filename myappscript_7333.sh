#!/bin/bash

# Exit immediately if any command fails
set -e

# ------------------ DEFAULTS ------------------
REPO=""
DOCKERHUB_USER=""
APP_NAME="my-appscript-7333"
TAG="latest"
NAMESPACE="default"
PORT=8000
# ----------------------------------------------

# ------------------ MINIKUBE PATH DETECTION ------------------
# Try to find minikube.exe automatically in common locations
if command -v minikube >/dev/null 2>&1; then
    MINIKUBE=$(command -v minikube)
elif [[ -f "/c/minikube/minikube.exe" ]]; then
    MINIKUBE="/c/minikube/minikube.exe"
elif [[ -f "/c/Program Files/Kubernetes/Minikube/minikube.exe" ]]; then
    MINIKUBE="/c/Program Files/Kubernetes/Minikube/minikube.exe"
elif [[ -f "/c/my files/minikube/minikube.exe" ]]; then
    MINIKUBE="/c/my files/minikube/minikube.exe"
else
    echo "ERROR: minikube.exe not found. Please install Minikube or add it to PATH."
    exit 1
fi

# Convert backslashes to forward slashes (Git Bash-friendly)
MINIKUBE=$(echo "$MINIKUBE" | sed 's|\\|/|g')

echo ">>> Using Minikube executable: $MINIKUBE"
# -------------------------------------------------------------

usage() {
  echo "Usage: $0 --repo <git_repo_url> --user <dockerhub_user> [--app <app_name>] [--tag <tag>] [--namespace <ns>] [--port <container_port>]"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) REPO="$2"; shift 2 ;;
    --user) DOCKERHUB_USER="$2"; shift 2 ;;
    --app) APP_NAME="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [[ -z "$REPO" || -z "$DOCKERHUB_USER" ]]; then
  echo "ERROR: --repo and --user are required"
  usage
fi

DOCKERHUB_REPO="$DOCKERHUB_USER/$APP_NAME"

# Clone repo
echo ">>> Cloning repo $REPO..."
rm -rf "$APP_NAME"
git clone "$REPO" "$APP_NAME"
cd "$APP_NAME"

# Build Docker image
echo ">>> Building Docker image..."
docker build -t "$DOCKERHUB_REPO:$TAG" .

# Push to Docker Hub
echo ">>> Logging in to Docker Hub..."
docker login -u "$DOCKERHUB_USER"
echo ">>> Pushing image to Docker Hub..."
docker push "$DOCKERHUB_REPO:$TAG"

# ------------------ Kubernetes Context Detection ------------------
echo ">>> Checking Kubernetes contexts..."
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")

if [[ "$CURRENT_CONTEXT" == "minikube" ]]; then
  echo ">>> Already using Minikube context."
else
  echo ">>> No valid current context, switching to Minikube..."
  if ! kubectl config get-contexts | grep -q "minikube"; then
    echo ">>> Minikube context missing, fixing with update-context..."
    "$MINIKUBE" update-context
  fi
  kubectl config use-context minikube
fi

# Ensure Minikube is running
if ! "$MINIKUBE" status >/dev/null 2>&1; then
  echo ">>> Minikube not running. Starting Minikube..."
  "$MINIKUBE" start
else
  echo ">>> Minikube is already running."
fi

# Delete old deployment/service if exists
echo ">>> Cleaning old deployment/service..."
kubectl delete deployment "$APP_NAME" --ignore-not-found -n "$NAMESPACE"
kubectl delete service "$APP_NAME" --ignore-not-found -n "$NAMESPACE"

# Apply Kubernetes Deployment + Service
echo ">>> Creating Kubernetes Deployment & Service..."
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: $APP_NAME
        image: $DOCKERHUB_REPO:$TAG
        ports:
        - containerPort: $PORT
---
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
spec:
  selector:
    app: $APP_NAME
  ports:
  - protocol: TCP
    port: 80
    targetPort: $PORT
  type: NodePort
EOF

echo ">>> Deployment applied successfully!"

# ------------------ Get Service URL ------------------
NODE_PORT=$(kubectl get service "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
MINIKUBE_IP=$("$MINIKUBE" ip)
APP_URL="http://$MINIKUBE_IP:$NODE_PORT"

echo ">>> Your application should be accessible at:"
echo ">>> $APP_URL"
