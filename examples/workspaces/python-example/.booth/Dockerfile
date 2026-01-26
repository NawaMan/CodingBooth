# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}


# Customizations
ARG PY_VERSION=3.12
ARG JDK_VERSION=24


RUN python--setup.sh ${PY_VERSION}
RUN jdk--setup.sh    ${JDK_VERSION}

RUN python-code-extension--setup.sh                         || [[ $? -eq 42 ]]
RUN jupyter-code-extension--setup.sh                        || [[ $? -eq 42 ]]

RUN pycharm--setup.sh                                       || [[ $? -eq 42 ]]
RUN jetbrains-plugin--setup.sh pycharm ru.adelf.idea.dotenv || [[ $? -eq 42 ]]

RUN claude-code--setup.sh                                   || [[ $? -eq 42 ]]
RUN antigravity--setup.sh                                   || [[ $? -eq 42 ]]
