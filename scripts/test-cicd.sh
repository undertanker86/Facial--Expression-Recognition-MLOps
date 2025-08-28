#!/bin/bash

# Test CI/CD Pipeline for FER Project
# This script tests both code updates and model updates

set -e

echo "🧪 Testing CI/CD Pipeline for FER Project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/undertanker86/Facial--Expression-Recognition-MLOps.git"
BRANCH="main"

# Check if git is available
check_git() {
    echo "🔍 Checking git..."
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}❌ git is required but not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ git check passed${NC}"
}

# Check if we're in a git repository
check_repository() {
    echo "📁 Checking repository..."
    
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ Not in a git repository${NC}"
        exit 1
    fi
    
    # Check remote origin
    if ! git remote get-url origin &> /dev/null; then
        echo -e "${RED}❌ No remote origin configured${NC}"
        exit 1
    fi
    
    CURRENT_REMOTE=$(git remote get-url origin)
    if [ "$CURRENT_REMOTE" != "$REPO_URL" ]; then
        echo -e "${YELLOW}⚠️ Remote origin mismatch${NC}"
        echo "Current: $CURRENT_REMOTE"
        echo "Expected: $REPO_URL"
        echo "Do you want to continue? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✅ Repository check passed${NC}"
}

# Test code update
test_code_update() {
    echo ""
    echo -e "${BLUE}📝 Testing Code Update Pipeline...${NC}"
    
    # Create a test file
    TEST_FILE="test-cicd-$(date +%s).txt"
    echo "Test CI/CD pipeline - $(date)" > "$TEST_FILE"
    
    # Add and commit
    git add "$TEST_FILE"
    git commit -m "Test CI/CD pipeline - Code update $(date)"
    
    echo -e "${YELLOW}⚠️ Ready to push code update${NC}"
    echo "This will trigger Jenkins CI/CD pipeline for code deployment"
    echo "Do you want to push? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "🚀 Pushing code update..."
        git push origin main
        
        echo -e "${GREEN}✅ Code update pushed successfully!${NC}"
        echo "Jenkins should now be triggered for code deployment"
        
        # Cleanup test file
        git rm "$TEST_FILE"
        git commit -m "Remove test file"
        git push origin main
    else
        echo "⏭️ Skipping code update push"
        git reset --hard HEAD~1
        rm -f "$TEST_FILE"
    fi
}

# Test model update
test_model_update() {
    echo ""
    echo -e "${BLUE}🚀 Testing Model Update Pipeline...${NC}"
    
    # Check if hybrid model manager is available
    if [ ! -f "src/hybrid_model_manager.py" ]; then
        echo -e "${RED}❌ Hybrid model manager not found${NC}"
        return 1
    fi
    
    # Create a test model file
    TEST_MODEL="model/test_model_$(date +%s).pth"
    echo "test model content for CI/CD testing" > "$TEST_MODEL"
    
    echo -e "${YELLOW}⚠️ Ready to test model update${NC}"
    echo "This will:"
    echo "1. Update model metadata"
    echo "2. Create version tag"
    echo "3. Push to GitHub"
    echo "4. Trigger Jenkins CI/CD for model deployment"
    echo "Do you want to proceed? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "🧪 Testing model update..."
        
        # Test the hybrid model manager
        python -c "
from src.hybrid_model_manager import HybridModelManager
manager = HybridModelManager()
manager.handle_model_update('$TEST_MODEL', 'Test model update for CI/CD pipeline testing')
"
        
        echo -e "${GREEN}✅ Model update test completed!${NC}"
        echo "Check GitHub for the new tag and Jenkins for the pipeline"
        
        # Cleanup test model
        rm -f "$TEST_MODEL"
        git add .
        git commit -m "Cleanup test model files"
        git push origin main
    else
        echo "⏭️ Skipping model update test"
        rm -f "$TEST_MODEL"
    fi
}

# Show pipeline status
show_pipeline_status() {
    echo ""
    echo -e "${BLUE}📊 Pipeline Status:${NC}"
    
    echo "=== Git Status ==="
    git status --porcelain
    
    echo ""
    echo "=== Recent Commits ==="
    git log --oneline -5
    
    echo ""
    echo "=== Recent Tags ==="
    git tag --sort=-version:refname | head -5
    
    echo ""
    echo "=== Remote Branches ==="
    git branch -r
}

# Show Jenkins information
show_jenkins_info() {
    echo ""
    echo -e "${BLUE}🔧 Jenkins Information:${NC}"
    
    echo "=== Job URL ==="
    echo "https://your-jenkins-url/job/fer-emotion-recognition/"
    
    echo ""
    echo "=== Webhook URL ==="
    echo "https://your-jenkins-url/github-webhook/"
    
    echo ""
    echo "=== Manual Build ==="
    echo "curl -X POST https://your-jenkins-url/job/fer-emotion-recognition/build"
    
    echo ""
    echo -e "${YELLOW}⚠️ Replace 'your-jenkins-url' with actual Jenkins URL${NC}"
}

# Show monitoring information
show_monitoring_info() {
    echo ""
    echo -e "${BLUE}📊 Monitoring Information:${NC}"
    
    echo "=== Prometheus ==="
    echo "URL: http://prometheus.local (or port-forward to 9090)"
    
    echo ""
    echo "=== Grafana ==="
    echo "URL: http://grafana.local (or port-forward to 3000)"
    echo "Credentials: admin / admin123"
    
    echo ""
    echo "=== Jaeger ==="
    echo "URL: http://jaeger.local (or port-forward to 16686)"
    
    echo ""
    echo "=== Port-forward Commands ==="
    echo "kubectl port-forward -n fer-project svc/prometheus 9090:9090"
    echo "kubectl port-forward -n fer-project svc/grafana 3000:3000"
    echo "kubectl port-forward -n fer-project svc/jaeger 16686:16686"
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  FER Project CI/CD Test${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    check_git
    check_repository
    
    echo ""
    echo -e "${BLUE}🎯 Available Tests:${NC}"
    echo "1. Code Update Pipeline Test"
    echo "2. Model Update Pipeline Test"
    echo "3. Show Pipeline Status"
    echo "4. Show Jenkins Information"
    echo "5. Show Monitoring Information"
    echo "6. Run All Tests"
    echo ""
    
    echo "Select test to run (1-6):"
    read -r choice
    
    case $choice in
        1)
            test_code_update
            ;;
        2)
            test_model_update
            ;;
        3)
            show_pipeline_status
            ;;
        4)
            show_jenkins_info
            ;;
        5)
            show_monitoring_info
            ;;
        6)
            test_code_update
            test_model_update
            show_pipeline_status
            show_jenkins_info
            show_monitoring_info
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}🎉 Test completed successfully!${NC}"
}

# Run main function
main "$@"
