FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x entrypoint.sh

EXPOSE 8080

ENV BOT_HOST=host.docker.internal
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["./entrypoint.sh"]
