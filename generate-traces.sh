#!/bin/bash

echo "🚀 Generating traces and metrics for FER service..."

# Create a simple test image (1x1 pixel PNG)
echo "📸 Creating test image..."
convert -size 1x1 xc:white test.png

# Send multiple POST requests to /predict
echo "📤 Sending POST requests to /predict..."
for i in $(seq 1 15); do
    echo "Request $i..."
    curl -s -X POST \
        -H "Host: fer.local" \
        -F "file=@test.png" \
        http://127.0.0.1:8080/predict > /dev/null
    
    # Small delay between requests
    sleep 0.5
done

# Clean up test image
rm -f test.png

echo "✅ Trace generation completed!"
echo ""
echo "🔍 Check the following:"
echo "1. Grafana dashboards should now show data for all panels"
echo "2. Jaeger should show traces for 'fer-service'"
echo "3. Prometheus should have populated metrics"
echo ""
echo "📊 To view results:"
echo "  - Grafana: http://grafana.fer.local (admin/admin)"
echo "  - Jaeger: http://jaeger.fer.local"
echo "  - Prometheus: http://prometheus.fer.local"
