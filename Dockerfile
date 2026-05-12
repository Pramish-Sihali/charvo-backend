FROM python:3.11-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

# Install deps as a separate layer for better caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the application code (migrations/, .env are excluded by .dockerignore).
COPY app ./app

USER appuser

EXPOSE 8000

# ECS task definition pins containerPort 8000; ALB target group also targets 8000.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status==200 else 1)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
