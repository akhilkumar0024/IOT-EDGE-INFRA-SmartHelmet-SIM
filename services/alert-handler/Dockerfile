FROM python:3.11-slim

# Unbuffered stdout so logs reach CloudWatch promptly, and no .pyc writing
# because the application directory is not writable by the runtime user below.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ .

# Run as non-root. Flagged by trivy as DS-0002 (and missed by hadolint). These
# services write nothing to the local filesystem - they log to stdout - so a
# read-only application directory is fine, and port 8080 is above 1024.
# Numeric ids are used to satisfy hadolint DL3066; the passwd entry is still
# created so the uid resolves to a name.
RUN groupadd --gid 10001 appuser \
 && useradd --uid 10001 --gid 10001 --create-home appuser
USER 10001:10001

CMD ["python", "main.py"]
