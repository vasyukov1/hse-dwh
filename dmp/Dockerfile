FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir pyyaml pymysql kafka-python

COPY . .

CMD ["python", "main.py"]
