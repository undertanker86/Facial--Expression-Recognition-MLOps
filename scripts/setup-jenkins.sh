#!/bin/bash

# Setup Jenkins CI/CD for FER Project
# This script helps setup Jenkins job and configuration

set -e

echo "🚀 Setting up Jenkins CI/CD for FER Project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"
JOB_NAME="fer-emotion-recognition"
REPO_URL="https://github.com/undertanker86/Facial--Expression-Recognition-MLOps.git"

# Check if required tools are installed
check_requirements() {
    echo "🔍 Checking requirements..."
    
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}❌ curl is required but not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠️ jq is recommended for JSON parsing${NC}"
    fi
    
    echo -e "${GREEN}✅ Requirements check passed${NC}"
}

# Test Jenkins connection
test_jenkins_connection() {
    echo "🔗 Testing Jenkins connection..."
    
    if curl -s --user "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL" > /dev/null; then
        echo -e "${GREEN}✅ Jenkins connection successful${NC}"
    else
        echo -e "${RED}❌ Cannot connect to Jenkins at $JENKINS_URL${NC}"
        echo "Please check:"
        echo "1. Jenkins is running"
        echo "2. URL is correct"
        echo "3. Credentials are valid"
        exit 1
    fi
}

# Create Jenkins job
create_jenkins_job() {
    echo "📝 Creating Jenkins job: $JOB_NAME"
    
    # Create job configuration XML
    cat > /tmp/job-config.xml << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1289.vd1c337fd5354">
  <description>Facial Emotion Recognition CI/CD Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.plugins.discarder.DiscarderProperty plugin="discarder@1.5">
      <strategy class="hudson.plugins.discarder.DefaultDiscarderStrategy">
        <daysToKeep>30</daysToKeep>
        <numToKeep>50</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>-1</artifactNumToKeep>
      </strategy>
    </hudson.plugins.discarder.DiscarderProperty>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>BRANCH</name>
          <description>Git branch to build</description>
          <defaultValue>main</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@3697.vb_4c1b_2ea_4f3c">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.15.0">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>$REPO_URL</url>
          <credentialsId>github-credentials</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
        <hudson.plugins.git.BranchSpec>
          <name>*/develop</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="list"/>
      <extensions>
        <hudson.plugins.git.extensions.impl.CloneOption>
          <shallow>false</shallow>
          <noTags>false</noTags>
          <reference/>
          <depth>0</depth>
          <honorRefspec>false</honorRefspec>
        </hudson.plugins.git.extensions.impl.CloneOption>
      </extensions>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>H/5 * * * *</spec>
    </hudson.triggers.SCMTrigger>
    <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.35.0">
      <spec/>
    </com.cloudbees.jenkins.GitHubPushTrigger>
  </triggers>
  <disabled>false</disabled>
</flow-definition>
EOF

    # Create job using Jenkins API
    if curl -s -X POST --user "$JENKINS_USER:$JENKINS_PASS" \
        "$JENKINS_URL/createItem?name=$JOB_NAME" \
        --data-binary @/tmp/job-config.xml \
        -H "Content-Type: application/xml" > /dev/null; then
        echo -e "${GREEN}✅ Jenkins job created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create Jenkins job${NC}"
        exit 1
    fi
    
    # Cleanup
    rm -f /tmp/job-config.xml
}

# Setup credentials
setup_credentials() {
    echo "🔐 Setting up Jenkins credentials..."
    
    # Create Docker Hub credentials
    cat > /tmp/dockerhub-credentials.xml << EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl plugin="credentials@1271.v54b_1c6388a_8">
  <scope>GLOBAL</scope>
  <id>dockerhub-credentials</id>
  <description>Docker Hub credentials for FER project</description>
  <username>undertanker86</username>
  <password>YOUR_DOCKER_HUB_PASSWORD</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF

    # Create GitHub credentials
    cat > /tmp/github-credentials.xml << EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl plugin="credentials@1271.v54b_1c6388a_8">
  <scope>GLOBAL</scope>
  <id>github-credentials</id>
  <description>GitHub credentials for FER project</description>
  <username>undertanker86</username>
  <password>YOUR_GITHUB_TOKEN</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF

    echo -e "${YELLOW}⚠️ Please manually create credentials in Jenkins:${NC}"
    echo "1. Go to Jenkins > Manage Jenkins > Credentials"
    echo "2. Create 'dockerhub-credentials' with your Docker Hub password"
    echo "3. Create 'github-credentials' with your GitHub token"
    echo "4. Update the XML files above with real credentials"
    
    # Cleanup
    rm -f /tmp/dockerhub-credentials.xml /tmp/github-credentials.xml
}

# Setup webhook
setup_webhook() {
    echo "🔗 Setting up GitHub webhook..."
    
    echo -e "${YELLOW}⚠️ Please manually setup GitHub webhook:${NC}"
    echo "1. Go to your GitHub repository"
    echo "2. Settings > Webhooks > Add webhook"
    echo "3. Payload URL: $JENKINS_URL/github-webhook/"
    echo "4. Content type: application/json"
    echo "5. Events: Just the push event"
    echo "6. Active: ✓"
}

# Test pipeline
test_pipeline() {
    echo "🧪 Testing pipeline..."
    
    # Trigger build
    if curl -s -X POST --user "$JENKINS_USER:$JENKINS_PASS" \
        "$JENKINS_URL/job/$JOB_NAME/build" > /dev/null; then
        echo -e "${GREEN}✅ Pipeline build triggered successfully${NC}"
        echo "Check build status at: $JENKINS_URL/job/$JOB_NAME/"
    else
        echo -e "${RED}❌ Failed to trigger pipeline build${NC}"
    fi
}

# Show next steps
show_next_steps() {
    echo ""
    echo -e "${BLUE}🎯 Next Steps:${NC}"
    echo "1. ✅ Jenkins job created: $JOB_NAME"
    echo "2. 🔐 Setup credentials in Jenkins"
    echo "3. 🔗 Setup GitHub webhook"
    echo "4. 🧪 Test pipeline"
    echo ""
    echo -e "${BLUE}📚 Useful Commands:${NC}"
    echo "• View job: $JENKINS_URL/job/$JOB_NAME/"
    echo "• Build job: curl -X POST --user user:pass $JENKINS_URL/job/$JOB_NAME/build"
    echo "• View logs: $JENKINS_URL/job/$JOB_NAME/lastBuild/console"
    echo ""
    echo -e "${BLUE}🔧 Manual Setup Required:${NC}"
    echo "• Docker Hub credentials"
    echo "• GitHub personal access token"
    echo "• Kubernetes context configuration"
    echo "• Monitoring stack deployment"
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  FER Project Jenkins Setup${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    check_requirements
    test_jenkins_connection
    create_jenkins_job
    setup_credentials
    setup_webhook
    test_pipeline
    show_next_steps
    
    echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
}

# Run main function
main "$@"
