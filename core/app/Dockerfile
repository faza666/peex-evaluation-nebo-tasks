# Until #24 this was python:3.8-slim, which is end-of-life: its OS packages had CRITICAL
# findings with fixes, so the Trivy gate in docker-build.yml stopped every push (Task 2,
# failure scenario 4). CI lint and tests run in this same image (in-runtime-image.sh).
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    FLASK_APP=bootstrap.py

WORKDIR /srv/menu

# Dependencies first, so this layer is reused while only the code changes.
COPY requirements.txt .
RUN pip install --root-user-action=ignore -r requirements.txt

COPY . .

# Non-root user. It owns the app directory because the default SQLite database lives there.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin menu \
    && chown -R menu /srv/menu
USER 10001

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

# Migrate, seed (only inserts when the table is empty), then hand PID 1 to gunicorn.
CMD ["sh", "-c", "flask db upgrade && python seed.py && exec gunicorn -c gunicorn.conf.py app:app"]
