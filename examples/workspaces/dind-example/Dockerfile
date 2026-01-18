# Use a lightweight Python base image
FROM python:3.12-slim

# Set the working directory inside the container
WORKDIR /app

# Copy only necessary files
COPY server.py .
COPY www ./www

# Expose the server port
EXPOSE 8080

# Use a non-root user (for safety)
RUN useradd -m appuser
USER appuser

# Run the server
CMD ["python", "server.py"]
