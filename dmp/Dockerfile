FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y libpq-dev gcc && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir pyyaml psycopg2-binary kafka-python

COPY . .

CMD ["python", "main.py"]
