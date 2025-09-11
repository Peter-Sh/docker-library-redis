FROM python:3.11-slim-trixie

RUN apt update && apt -y install git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY . /release-automation
RUN pip install -e /release-automation

ENTRYPOINT ["release-automation"]
CMD ["--help"]
