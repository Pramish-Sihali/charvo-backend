# syntax=docker/dockerfile:1.7

# ── Builder stage: install deps into an isolated venv ──────────────────────
FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Strip cruft that has no runtime purpose: bytecode, tests, package metadata docs.
RUN find /opt/venv -depth -type d -name __pycache__ -exec rm -rf {} + \
 && find /opt/venv -depth -type d -name tests -exec rm -rf {} + \
 && find /opt/venv -depth -type d -name test -exec rm -rf {} + \
 && find /opt/venv -depth -name "*.pyc" -delete \
 && find /opt/venv -depth -name "*.pyo" -delete

# ── Runtime stage: copy only the venv + app code ───────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

RUN useradd --create-home --uid 10001 appuser

COPY app ./app

USER appuser

EXPOSE 8000

# ECS task definition pins containerPort 8000; ALB target group also targets 8000.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status==200 else 1)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
