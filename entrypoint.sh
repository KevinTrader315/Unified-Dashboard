#!/bin/bash
set -e

exec gunicorn app:app \
    --bind 0.0.0.0:8080 \
    --worker-class gthread \
    --workers 2 \
    --threads 8 \
    --timeout 600 \
    --access-logfile - \
    --error-logfile -
