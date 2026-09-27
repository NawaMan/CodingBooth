#!/bin/bash
# Runs inside the booth. Prints KEY=value lines for test--boothfile-jenv.sh to assert on.
#
# Each probe starts a fresh login shell, the way `booth -- <cmd>` (non-interactive) and a
# terminal (interactive, prompt hooks run) each get their environment.
set -u

# Major version of the JDK that JAVA_HOME points at, or "none" when it points at nothing.
# The -n matters: an empty JAVA_HOME makes the path /bin/java, which exists (the JDK's
# update-alternatives link), so without it a blank JAVA_HOME would pass as the JDK.
jh_major() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    "$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/'
  else
    echo none
  fi
}
# Major version of the `java` on PATH (jenv's shim, once jenv is set up).
path_major() { java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/'; }
export -f jh_major path_major

ni() { bash -lc "$1" 2>/dev/null; }
ia() { printf '%s\n' "$1" | bash -li 2>/dev/null | grep -E '^[A-Z_]+='; }

# --- no jenv version chosen ("system"): JAVA_HOME is the booth's JDK ---
ni 'echo NI_SYSTEM=$(jh_major) NI_SYSTEM_RAW=$JAVA_HOME'
ia 'echo IA_SYSTEM=$(jh_major) IA_SYSTEM_RAW=$JAVA_HOME'

# --- a second JDK, and jenv pointed at the first one ---
# Installing 17 rewrites the JDK profile to JAVA_HOME=/opt/jdk17, so a JAVA_HOME
# still at 17 after `jenv global 21` means the JDK profile won over jenv.
sudo /opt/codingbooth/setups/jdk--setup.sh 17 temurin >/tmp/jdk17.log 2>&1
echo "JDK17_RC=$?"
ni 'jenv add /opt/jdk21 >/dev/null 2>&1; jenv add /opt/jdk17 >/dev/null 2>&1; jenv global 21 >/dev/null 2>&1; echo JENV_GLOBAL=$(jenv version-name)'

ni 'echo NI_CHOSEN_PATH=$(path_major)'
ni 'echo NI_CHOSEN=$(jh_major) NI_CHOSEN_RAW=$JAVA_HOME'
ia 'echo IA_CHOSEN=$(jh_major) IA_CHOSEN_RAW=$JAVA_HOME'
