# Dockerfile for On-Premises Container Monitor
FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY src/ .

# Create non-root user for security
RUN useradd -m -u 1000 monitor && \
    chown -R monitor:monitor /app
USER monitor

# Set default environment variables
ENV HEARTBEAT_INTERVAL=300
ENV AWS_REGION=us-east-1
ENV CLOUDWATCH_NAMESPACE=ContainerMonitoring/Heartbeat
ENV LOG_LEVEL=INFO
ENV ENABLE_HEALTH_ENDPOINT=false
ENV HEALTH_PORT=8080

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD python health_check.py

# Expose health endpoint port (optional)
EXPOSE 8080

# Run the monitoring script
CMD ["python", "monitor.py"]