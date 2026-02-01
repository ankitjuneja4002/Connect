#!/bin/bash

# Script to run Connect Backend locally

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting Connect Backend..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Creating from .env.example..."
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✅ Created .env file. Please update it with your configuration."
        echo "⚠️  You need to update at least:"
        echo "   - MAIL_USERNAME and MAIL_PASSWORD (for email functionality)"
        echo "   - JWT_SECRET (use a secure random string)"
        echo ""
        read -p "Press Enter to continue after updating .env file, or Ctrl+C to exit..."
    else
        echo "❌ .env.example not found. Please create .env file manually."
        exit 1
    fi
fi

# Load environment variables
while IFS= read -r line || [ -n "$line" ]; do
  # Skip comments and empty lines
  if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$line" ]]; then
    export "$line"
  fi
done < .env

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Start Docker services (MongoDB, Redis, Kafka)
echo "📦 Starting Docker services (MongoDB, Redis, Kafka)..."
docker compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
sleep 5

# Check MongoDB
echo "Checking MongoDB..."
until docker exec connect-mongodb mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
    echo "Waiting for MongoDB..."
    sleep 2
done
echo "✅ MongoDB is ready"

# Check Redis
echo "Checking Redis..."
until docker exec connect-redis redis-cli -a redispassword ping > /dev/null 2>&1; do
    echo "Waiting for Redis..."
    sleep 2
done
echo "✅ Redis is ready"

# Check Kafka
echo "Checking Kafka..."
until docker exec connect-kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; do
    echo "Waiting for Kafka..."
    sleep 2
done
echo "✅ Kafka is ready"

echo ""
echo "✅ All services are ready!"
echo ""
echo "🔧 Starting Spring Boot application..."
echo ""

# Determine which Maven to use
MAVEN_CMD=""
if [ -f "./mvnw" ] && [ -f ".mvn/wrapper/maven-wrapper.properties" ]; then
    # Test if wrapper works
    if ./mvnw --version > /dev/null 2>&1; then
        MAVEN_CMD="./mvnw"
        echo "Using Maven wrapper..."
    else
        echo "⚠️  Maven wrapper failed, trying system Maven..."
        if command -v mvn > /dev/null 2>&1; then
            MAVEN_CMD="mvn"
            echo "Using system Maven..."
        else
            echo "❌ Neither Maven wrapper nor system Maven is available."
            exit 1
        fi
    fi
elif command -v mvn > /dev/null 2>&1; then
    MAVEN_CMD="mvn"
    echo "Using system Maven..."
else
    echo "❌ Maven wrapper not found and system Maven is not available."
    echo "Please install Maven or fix the wrapper setup."
    exit 1
fi

# Run Spring Boot application
$MAVEN_CMD spring-boot:run
