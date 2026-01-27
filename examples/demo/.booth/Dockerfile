# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Customizations
ARG JDK_VERSION=25
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11
ARG PY_VERSION=3.12
ARG GO_VERSION=1.25.4

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN python--setup.sh "${PY_VERSION}"
RUN jdk--setup.sh    "${JDK_VERSION}"
RUN go--setup.sh     "${GO_VERSION}"

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN mvn--setup.sh
RUN gradle--setup.sh
RUN jenv--setup.sh

RUN antigravity--setup.sh
RUN claude-code--setup.sh

RUN java-code-extension--setup.sh
RUN go-code-extension--setup.sh

RUN notebook--setup.sh
RUN python-nb-kernel--setup.sh
RUN bash-nb-kernel--setup.sh
RUN java-jjava-nb-kernel--setup.sh

