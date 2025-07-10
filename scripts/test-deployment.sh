#!/bin/bash

# Deployment Testing Script
# This script tests the deployed LLM-D service

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

NAMESPACE=${1:-default}

echo "Testing LLM-D deployment in namespace: $NAMESPACE"
echo "Model Name: $MODEL_NAME"

# Function to test direct pod access
test_direct_pod() {
    echo "=== Testing direct pod access ==="
    
    # Find the decode pod
    DECODE_POD=$(kubectl get pods -l app.kubernetes.io/name="$MODEL_NAME",app.kubernetes.io/component=decode -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$DECODE_POD" ]; then
        echo "ERROR: No decode pod found for model $MODEL_NAME"
        return 1
    fi
    
    DECODE_IP=$(kubectl get pod "$DECODE_POD" -o jsonpath='{.status.podIP}')
    echo "Decode pod: $DECODE_POD ($DECODE_IP)"
    
    # Test models endpoint
    echo "1. Testing models endpoint..."
    kubectl run curl-test-models --rm -i --restart=Never --image=curlimages/curl:latest -- \
        curl -s "http://$DECODE_IP:8000/v1/models" | jq .
    
    # Test completion endpoint
    echo "2. Testing completion endpoint..."
    kubectl run curl-test-completion --rm -i --restart=Never --image=curlimages/curl:latest -- \
        curl -s -X POST "http://$DECODE_IP:8000/v1/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL_NAME\", \"prompt\": \"Hello, I am\", \"max_tokens\": 16}" | jq .
}

# Function to test gateway access
test_gateway_access() {
    echo "=== Testing gateway access ==="
    
    # Get gateway IP
    GATEWAY_IP=$(kubectl get gateway "${MODEL_NAME}-gateway" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -z "$GATEWAY_IP" ]; then
        echo "WARNING: No gateway found for model $MODEL_NAME"
        return 1
    fi
    
    echo "Gateway IP: $GATEWAY_IP"
    
    # Test models endpoint via gateway
    echo "3. Testing models endpoint via gateway..."
    kubectl run curl-test-gateway-models --rm -i --restart=Never --image=curlimages/curl:latest -- \
        curl -s "http://$GATEWAY_IP:80/v1/models" | jq .
    
    # Test completion endpoint via gateway
    echo "4. Testing completion endpoint via gateway..."
    kubectl run curl-test-gateway-completion --rm -i --restart=Never --image=curlimages/curl:latest -- \
        curl -s -X POST "http://$GATEWAY_IP:80/v1/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL_NAME\", \"prompt\": \"Hello, I am\", \"max_tokens\": 16}" | jq .
}

# Function to test external access (requires authentication)
test_external_access() {
    echo "=== Testing external access ==="
    
    # Get external IP
    EXTERNAL_IP=$(kubectl get gateway "${MODEL_NAME}-gateway" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        echo "WARNING: No external IP available"
        return 1
    fi
    
    echo "External IP: $EXTERNAL_IP"
    echo "Testing external access with authentication..."
    
    # Test with gcloud auth token
    ACCESS_TOKEN=$(gcloud auth print-access-token)
    
    curl -i -X POST "http://$EXTERNAL_IP:80/v1/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"prompt\": \"Say something\",
            \"max_tokens\": 16,
            \"temperature\": 0.5
        }"
}

# Function to check deployment status
check_deployment_status() {
    echo "=== Checking deployment status ==="
    
    echo "Pods:"
    kubectl get pods -l app.kubernetes.io/name="$MODEL_NAME" -o wide
    
    echo "Services:"
    kubectl get services -l app.kubernetes.io/name="$MODEL_NAME"
    
    echo "ModelServices:"
    kubectl get modelservices "$MODEL_NAME" -o wide
    
    echo "Gateways:"
    kubectl get gateways "${MODEL_NAME}-gateway" -o wide 2>/dev/null || echo "No gateway found"
    
    echo "HTTPRoutes:"
    kubectl get httproutes -l app.kubernetes.io/name="$MODEL_NAME" -o wide 2>/dev/null || echo "No HTTPRoutes found"
}

# Main testing flow
main() {
    echo "Starting LLM-D deployment tests..."
    
    # Check deployment status first
    check_deployment_status
    
    # Wait for pods to be ready
    echo "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="$MODEL_NAME" --timeout=300s
    
    # Run tests
    test_direct_pod
    
    echo "Waiting 10 seconds before gateway tests..."
    sleep 10
    
    test_gateway_access || echo "Gateway tests failed or not available"
    
    echo "=== Test Summary ==="
    echo "✓ Direct pod access tested"
    echo "✓ Gateway access tested (if available)"
    echo "✓ Model: $MODEL_NAME"
    echo "✓ Namespace: $NAMESPACE"
    echo ""
    echo "For external access testing, run:"
    echo "  ./scripts/test-deployment.sh external"
    echo ""
    echo "All tests completed!"
}

# Handle command line arguments
case "${1:-}" in
    "external")
        test_external_access
        ;;
    *)
        main
        ;;
esac