# Hub of the shared proxy: python + docker CLI (to start a stopped project
# from the page: compose runs in a throwaway docker:cli container).
FROM python:3.13-alpine
RUN apk add --no-cache docker-cli
COPY hub.py /hub/hub.py
COPY static /hub/static
CMD ["python3", "-u", "/hub/hub.py"]
