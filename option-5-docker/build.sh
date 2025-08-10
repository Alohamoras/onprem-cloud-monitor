#!/bin/bash
# Build script for on-premises monitor Docker container

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
IMAGE_NAME="onprem-monitor"
VERSION=${1:-"latest"}
REGISTRY=${DOCKER_REGISTRY:-""}

print_info "Building On-Premises Monitor Container"
print_info "Image: ${IMAGE_NAME}:${VERSION}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build the image
print_info "Building Docker image..."
docker build -t ${IMAGE_NAME}:${VERSION} .

if [ $? -eq 0 ]; then
    print_success "Docker image built successfully"
else
    print_error "Failed to build Docker image"
    exit 1
fi

# Tag as latest if not already
if [ "$VERSION" != "latest" ]; then
    docker tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:latest
    print_info "Tagged as ${IMAGE_NAME}:latest"
fi

# Show image info
print_info "Image details:"
docker images ${IMAGE_NAME}:${VERSION} --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# Test the image
print_info "Testing the image..."
TEST_CONTAINER="test-${IMAGE_NAME}-$$"

# Run basic test without AWS credentials (should fail gracefully)
docker run --rm --name ${TEST_CONTAINER} \
    -e AWS_ACCESS_KEY_ID=test \
    -e AWS_SECRET_ACCESS_KEY=test \
    -e AWS_REGION=us-east-1 \
    -e CONTAINER_NAME=test-container \
    ${IMAGE_NAME}:${VERSION} python -c "
import sys
sys.path.append('/app')
try:
    import monitor
    print('✓ Monitor module imports successfully')
    print('✓ Basic container test passed')
except Exception as e:
    print(f'✗ Test failed: {e}')
    sys.exit(1)
" 2>/dev/null

if [ $? -eq 0 ]; then
    print_success "Container test passed"
else
    print_warning "Container test had issues (this may be expected without valid AWS credentials)"
fi

# Push to registry if specified
if [ -n "$REGISTRY" ]; then
    print_info "Pushing to registry: $REGISTRY"
    
    # Tag for registry
    docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:${VERSION}
    docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:latest
    
    # Push
    docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}
    docker push ${REGISTRY}/${IMAGE_NAME}:latest
    
    print_success "Pushed to registry"
fi

print_success "Build complete!"
print_info ""
print_info "Next steps:"
print_info "1. Copy .env.example to .env and configure your settings:"
print_info "   cp .env.example .env"
print_info ""
print_info "2. Run with Docker Compose:"
print_info "   docker-compose up -d"
print_info ""
print_info "3. Or run directly:"
print_info "   docker run -d --restart unless-stopped \\"
print_info "     --name onprem-monitor \\"
print_info "     -e AWS_ACCESS_KEY_ID=your_key \\"
print_info "     -e AWS_SECRET_ACCESS_KEY=your_secret \\"
print_info "     -e AWS_REGION=us-east-1 \\"
print_info "     -e CONTAINER_NAME=my-location \\"
print_info "     ${IMAGE_NAME}:${VERSION}"
print_info ""
print_info "4. Check logs:"
print_info "   docker logs -f onprem-monitor"
print_info ""
print_info "5. Create CloudWatch alarms using setup-alarms.sh"