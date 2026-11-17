ARG BASE_IMAGE=python:3.12-slim
FROM ${BASE_IMAGE}

ARG REQUIREMENTS_FILE=requirements.txt
ARG APP_VERSION=dev

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

WORKDIR /srv

COPY ${REQUIREMENTS_FILE} /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

COPY demo_app ./demo_app

# Run as an unprivileged user
RUN useradd --system --uid 10001 --no-create-home appuser
USER 10001

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:5000/health', timeout=2)"]

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "demo_app.main:application"]
