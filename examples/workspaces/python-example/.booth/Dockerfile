# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


# Customizations
ARG PY_VERSION=3.12
ARG JDK_VERSION=24


RUN python--setup.sh ${PY_VERSION}
RUN jdk--setup.sh    ${JDK_VERSION}

RUN python-code-extension--setup.sh
RUN jupyter-code-extension--setup.sh

RUN pycharm--setup.sh
RUN jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv

RUN claude-code--setup.sh
RUN antigravity--setup.sh
