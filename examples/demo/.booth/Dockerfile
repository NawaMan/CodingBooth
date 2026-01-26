# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Customizations
ARG JDK_VERSION=25
ARG JDK_VENDOR=temurin
ARG MVN_VERSION=3.9.11

# Given user is root and /opt/codingbooth/setups is in PATH (from base image)

RUN jdk--setup.sh    "${JDK_VERSION}"
RUN mvn--setup.sh
RUN gradle--setup.sh
RUN jenv--setup.sh

RUN go--setup.sh
RUN go-code-extension--setup.sh  || [[ $? -eq 42 ]]

# Force jbang run to not show download afterward.
RUN echo 'class Hi { public static void main(String[] args) { System.out.println("Hi again"); }}' | jbang -

RUN antigravity--setup.sh            || [[ $? -eq 42 ]]
RUN claude-code--setup.sh            || [[ $? -eq 42 ]]

RUN base-code-extension--setup.sh    || [[ $? -eq 42 ]]
RUN bash-code-extension--setup.sh    || [[ $? -eq 42 ]]
RUN python-code-extension--setup.sh  || [[ $? -eq 42 ]]
RUN java-code-extension--setup.sh    || [[ $? -eq 42 ]]

RUN java-jjava-nb-kernel--setup.sh
RUN bash-nb-kernel--setup.sh
