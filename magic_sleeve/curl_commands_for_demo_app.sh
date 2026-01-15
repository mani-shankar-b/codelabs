#!/bin/bash

# Tix Demo Applications - Curl Commands
# This script contains curl commands for testing all demo applications
# Make sure to port-forward services before running these commands

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service ports
WINTERFELL_PORT=30001
RAVEN_PORT=30002
EYRIE_PORT=30003
TYRION_PORT=30005

# Base URLs (assuming port-forward is set up)
WINTERFELL_URL="http://localhost:${WINTERFELL_PORT}"
RAVEN_URL="http://localhost:${RAVEN_PORT}"
EYRIE_URL="http://localhost:${EYRIE_PORT}"
TYRION_URL="http://localhost:${TYRION_PORT}"

# Namespace
NAMESPACE="demoapp"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Tix Demo Applications - Curl Commands${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if port-forward is running
check_port_forward() {
    local port=$1
    local service=$2
    if ! lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo -e "${YELLOW}⚠️  Warning: Port ${port} is not forwarded. Run:${NC}"
        echo -e "   kubectl port-forward -n ${NAMESPACE} svc/demo-${service} ${port}:${port}"
        echo ""
    fi
}

# ============================================================================
# WINTERFELL (Port 30001)
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}WINTERFELL Service (Port ${WINTERFELL_PORT})${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
check_port_forward ${WINTERFELL_PORT} "winterfell"

echo -e "${BLUE}# Health Check${NC}"
echo "curl ${WINTERFELL_URL}/winterfell/health"
echo ""

echo -e "${BLUE}# Search Movies by Name${NC}"
echo "curl \"${WINTERFELL_URL}/search/moviesByName?name=Avengers\""
echo ""

echo -e "${BLUE}# Search Movies by Name (Detailed)${NC}"
echo "curl \"${WINTERFELL_URL}/search/moviesByName?name=Avengers&isDetailed=true\""
echo ""

echo -e "${BLUE}# Auto Suggest${NC}"
echo "curl \"${WINTERFELL_URL}/search/suggest?query=ave\""
echo ""

echo -e "${BLUE}# Search Shows${NC}"
echo "curl \"${WINTERFELL_URL}/search/shows?name=Avengers\""
echo ""

echo -e "${BLUE}# Search Movies by Criteria (POST)${NC}"
echo "curl -X POST ${WINTERFELL_URL}/search/movies \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"name\": \"Avengers\", \"genre\": \"Action\"}'"
echo ""

echo -e "${BLUE}# Search Shows by Criteria (POST)${NC}"
echo "curl -X POST ${WINTERFELL_URL}/search/showsByCriteria \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"movieName\": \"Avengers\", \"date\": \"2024-01-15\"}'"
echo ""

echo -e "${BLUE}# Ingest Seed Data${NC}"
echo "curl -X POST ${WINTERFELL_URL}/ingest/seed-data"
echo ""

echo -e "${BLUE}# Ingest Movie${NC}"
echo "curl -X POST ${WINTERFELL_URL}/ingest/movie \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"name\": \"Avengers\", \"genre\": \"Action\", \"releaseDate\": \"2024-01-01\"}'"
echo ""

echo -e "${BLUE}# Ingest Movies (Bulk)${NC}"
echo "curl -X POST ${WINTERFELL_URL}/ingest/movies \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '[\"Avengers\", \"Iron Man\", \"Thor\"]'"
echo ""

echo -e "${BLUE}# Submit Review${NC}"
echo "curl -X POST ${WINTERFELL_URL}/review/submit \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"movieName\": \"Avengers\", \"rating\": 5, \"comment\": \"Great movie!\"}'"
echo ""

echo -e "${BLUE}# Edit Review${NC}"
echo "curl -X POST ${WINTERFELL_URL}/review/edit \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"movieName\": \"Avengers\", \"rating\": 4, \"comment\": \"Updated review\"}'"
echo ""

# ============================================================================
# RAVEN (Port 30002)
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}RAVEN Service (Port ${RAVEN_PORT})${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
check_port_forward ${RAVEN_PORT} "raven"

echo -e "${BLUE}# Health Check${NC}"
echo "curl ${RAVEN_URL}/dbooking/health"
echo ""

echo -e "${BLUE}# Get Hello (Simple Test)${NC}"
echo "curl ${RAVEN_URL}/dbooking/get-hello"
echo ""

echo -e "${BLUE}# Get Bookings for Show${NC}"
echo "curl -X POST \"${RAVEN_URL}/dbooking/get-bookings/show123\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"showId\": \"show123\", \"date\": \"2024-01-15\"}'"
echo ""

echo -e "${BLUE}# Get User Insights${NC}"
echo "curl ${RAVEN_URL}/user-insights/user123"
echo ""

echo -e "${BLUE}# Get User Insights Forecast${NC}"
echo "curl ${RAVEN_URL}/user-insights-forecast/user123"
echo ""

echo -e "${BLUE}# Get External Data${NC}"
echo "curl \"${RAVEN_URL}/external-data?query=movie+data\""
echo ""

# ============================================================================
# EYRIE (Port 30003)
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}EYRIE Service (Port ${EYRIE_PORT})${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
check_port_forward ${EYRIE_PORT} "eyrie"

echo -e "${BLUE}# Ingest Show Bookings${NC}"
echo "curl -X POST ${EYRIE_URL}/ingest \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '[\"show1\", \"show2\", \"show3\"]'"
echo ""

echo -e "${BLUE}# Book Show${NC}"
echo "curl -X POST ${EYRIE_URL}/bookShow \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"showId\": 1, \"userId\": \"user123\", \"userBookedSeatNumber\": [\"A1\", \"A2\"]}'"
echo ""

echo -e "${BLUE}# Get Booked Seats${NC}"
echo "curl \"${EYRIE_URL}/getBookedSeats?showId=1\""
echo ""

echo -e "${BLUE}# Get User Booking History${NC}"
echo "curl -X POST \"${EYRIE_URL}/getUserBookingHistory?userId=user123\" \\"
echo "  -H \"Content-Type: application/json\""
echo ""

echo -e "${BLUE}# Check if User is Past Customer${NC}"
echo "curl \"${EYRIE_URL}/isUserPastCustomer?userId=user123\""
echo ""

# ============================================================================
# TYRION (Port 30005)
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}TYRION Service (Port ${TYRION_PORT})${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
check_port_forward ${TYRION_PORT} "tyrion"

echo -e "${BLUE}# Health Check${NC}"
echo "curl ${TYRION_URL}/tyrion/health"
echo ""

echo -e "${BLUE}# Ingest Seed Data${NC}"
echo "curl -X POST ${TYRION_URL}/ingest/seed-data"
echo ""

echo -e "${BLUE}# Ingest Users${NC}"
echo "curl -X POST ${TYRION_URL}/ingest/users \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '[\"user1\", \"user2\", \"user3\"]'"
echo ""

echo -e "${BLUE}# Ingest Reviews${NC}"
echo "curl -X POST ${TYRION_URL}/ingest/reviews \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '[\"review1\", \"review2\", \"review3\"]'"
echo ""

echo -e "${BLUE}# Get Reviews for Movie${NC}"
echo "curl \"${TYRION_URL}/reviewsForMovie?movieId=1\""
echo ""

echo -e "${BLUE}# Get Rating for Movie${NC}"
echo "curl \"${TYRION_URL}/ratingForMovie?movieId=1\""
echo ""

# ============================================================================
# PORT-FORWARD COMMANDS
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Port-Forward Commands${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "# Port-forward all services (run in separate terminals or background):"
echo ""
echo "# Winterfell"
echo "kubectl port-forward -n ${NAMESPACE} svc/demo-winterfell ${WINTERFELL_PORT}:${WINTERFELL_PORT} &"
echo ""
echo "# Raven"
echo "kubectl port-forward -n ${NAMESPACE} svc/demo-raven ${RAVEN_PORT}:${RAVEN_PORT} &"
echo ""
echo "# Eyrie"
echo "kubectl port-forward -n ${NAMESPACE} svc/demo-eyrie ${EYRIE_PORT}:${EYRIE_PORT} &"
echo ""
echo "# Tyrion"
echo "kubectl port-forward -n ${NAMESPACE} svc/demo-tyrion ${TYRION_PORT}:${TYRION_PORT} &"
echo ""
echo "# To stop all port-forwards:"
echo "pkill -f 'kubectl port-forward'"
echo ""

# ============================================================================
# QUICK TEST COMMANDS
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Quick Test Commands${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "# Test all health endpoints:"
echo "curl ${WINTERFELL_URL}/winterfell/health && echo \" - Winterfell OK\""
echo "curl ${RAVEN_URL}/dbooking/health && echo \" - Raven OK\""
echo "curl ${TYRION_URL}/tyrion/health && echo \" - Tyrion OK\""
echo ""
echo "# Ingest seed data (run after services are up):"
echo "curl -X POST ${WINTERFELL_URL}/ingest/seed-data"
echo "curl -X POST ${TYRION_URL}/ingest/seed-data"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}End of Curl Commands${NC}"
echo -e "${BLUE}========================================${NC}"

