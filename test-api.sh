#!/bin/bash

# Quick API Test Script for Connect Backend
# Make sure the application is running before executing this script

BASE_URL="http://localhost:8080"

echo "🔍 Testing Connect Backend API..."
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if server is running
check_server() {
    echo "Checking if server is running..."
    if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Server is running!${NC}"
        return 0
    else
        echo -e "${RED}❌ Server is not running on $BASE_URL${NC}"
        echo "Please start the server first using: ./run-local.sh"
        return 1
    fi
}

# Check server first
if ! check_server; then
    exit 1
fi

echo ""
echo "=================================="
echo ""

# 1. Health Check
echo "1️⃣  Testing Health Endpoint..."
HEALTH_RESPONSE=$(curl -s "$BASE_URL/health")
if [ "$HEALTH_RESPONSE" == "Health is ok" ]; then
    echo -e "${GREEN}✅ Health check passed: $HEALTH_RESPONSE${NC}"
else
    echo -e "${RED}❌ Health check failed: $HEALTH_RESPONSE${NC}"
fi
echo ""

# 2. Get All Rooms (Public endpoint)
echo "2️⃣  Testing Get All Rooms..."
ROOMS_RESPONSE=$(curl -s "$BASE_URL/room/getall")
if echo "$ROOMS_RESPONSE" | grep -q "\[\]" || echo "$ROOMS_RESPONSE" | grep -q "name"; then
    echo -e "${GREEN}✅ Get rooms endpoint working${NC}"
    echo "Response: $ROOMS_RESPONSE"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $ROOMS_RESPONSE${NC}"
fi
echo ""

# 3. Test Signup (will fail if email config is missing, but endpoint should respond)
echo "3️⃣  Testing Signup Endpoint..."
SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/signup" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser'$(date +%s)'",
    "email": "test'$(date +%s)'@example.com",
    "password": "password123",
    "role": "USER"
  }')

if echo "$SIGNUP_RESPONSE" | grep -q "OTP\|error\|Exception"; then
    echo -e "${GREEN}✅ Signup endpoint responding${NC}"
    echo "Response: $SIGNUP_RESPONSE"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $SIGNUP_RESPONSE${NC}"
fi
echo ""

# 4. Test Invalid Login (should return error)
echo "4️⃣  Testing Login Endpoint (with invalid credentials)..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "nonexistent",
    "password": "wrongpassword"
  }')

if echo "$LOGIN_RESPONSE" | grep -q "error\|Exception\|Invalid\|Unauthorized"; then
    echo -e "${GREEN}✅ Login endpoint responding correctly to invalid credentials${NC}"
    echo "Response: $LOGIN_RESPONSE"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $LOGIN_RESPONSE${NC}"
fi
echo ""

# 5. Test Token Verification (without token - should fail)
echo "5️⃣  Testing Token Verification (without token)..."
TOKEN_RESPONSE=$(curl -s "$BASE_URL/api/verify-token")
if echo "$TOKEN_RESPONSE" | grep -q "Missing\|Unauthorized\|401"; then
    echo -e "${GREEN}✅ Token verification endpoint correctly rejecting missing token${NC}"
    echo "Response: $TOKEN_RESPONSE"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $TOKEN_RESPONSE${NC}"
fi
echo ""

echo "=================================="
echo ""
echo -e "${GREEN}✅ Basic API tests completed!${NC}"
echo ""
echo "📝 Next Steps:"
echo "1. Signup a user: curl -X POST $BASE_URL/auth/signup -H 'Content-Type: application/json' -d '{\"username\":\"test\",\"email\":\"test@example.com\",\"password\":\"pass123\",\"role\":\"USER\"}'"
echo "2. Check your email for OTP (if email is configured)"
echo "3. Verify OTP: curl -X POST $BASE_URL/auth/signup/verifyOTP -H 'Content-Type: application/json' -d '{\"email\":\"test@example.com\",\"otp\":\"YOUR_OTP\"}'"
echo "4. Login: curl -X POST $BASE_URL/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"test\",\"password\":\"pass123\"}'"
echo "5. Use the token from login for protected endpoints"
echo ""
echo "For more details, see TESTING.md"
