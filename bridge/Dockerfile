FROM python:3.12-slim
RUN pip install --no-cache-dir pydicom==2.4.4 requests==2.32.3
COPY bridge.py /bridge.py
CMD ["python", "-u", "/bridge.py"]
