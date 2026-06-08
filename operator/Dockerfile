FROM python:3.11-slim

WORKDIR /operator

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY handlers/ handlers/

CMD ["kopf", "run", "--all-namespaces", "--liveness=http://0.0.0.0:8080/healthz", "main.py"]
