# Use lightweight Python image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app code
COPY app.py .

# Run app
CMD ["python", "app.py"]
