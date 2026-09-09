#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Usage in Boothfile:  setup eclipse-import-project [DEFAULT|GENERAL|MAVEN|GRADLE]
#
# Why this needs a real Eclipse application and not just a dropped file:
# Eclipse's per-project ".location" file (written under
# <workspace>/.metadata/.plugins/org.eclipse.core.resources/.projects/<name>/) records
# where a project lives on disk, but a project only actually shows up in the
# workspace once it's also in Eclipse's resource tree -- and that tree is private,
# in-memory state that only Eclipse's own IWorkspace/IProject API mutates correctly.
# Hand-writing .location alone (an earlier version of this script did that) leaves
# the tree untouched, so Eclipse never surfaces the project -- confirmed by
# launching a real booth and checking the workspace's resource-tree snapshot.
#
# So instead: at build time (here, as root, with Eclipse's own bundled jars on the
# classpath) we compile a tiny Equinox application -- cb.importproject.app -- that
# calls the real IProject.create()/.open() APIs, and drop it into Eclipse's
# dropins/ folder. At container startup we just launch Eclipse headlessly with
# that application, pointed at the project directory. Verified end-to-end: project
# appears in the workspace's resource tree, with JDT/EGit/Buildship wired up
# exactly as if imported by hand.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"

LEVEL=72
KIND="${1:-DEFAULT}"
ECLIPSE_DIR="$(readlink -f /opt/eclipse 2>/dev/null || true)"

if [ -z "$ECLIPSE_DIR" ] || [ ! -d "$ECLIPSE_DIR/plugins" ]; then
  skip_setup "$SCRIPT_NAME" "Eclipse not installed (select 'eclipse' before 'eclipse-import-project')"
fi
if ! command -v javac >/dev/null 2>&1; then
  skip_setup "$SCRIPT_NAME" "no JDK (javac) available"
fi

WORK="$(mktemp -d)"
mkdir -p "$WORK/src/cb/importproject" "$WORK/build/META-INF"

cat > "$WORK/src/cb/importproject/Application.java" <<'JAVAEOF'
package cb.importproject;

import java.io.File;

import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IProjectDescription;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.resources.IWorkspace;
import org.eclipse.core.resources.ResourcesPlugin;
import org.eclipse.core.runtime.IProgressMonitor;
import org.eclipse.core.runtime.NullProgressMonitor;
import org.eclipse.core.runtime.Path;
import org.eclipse.equinox.app.IApplication;
import org.eclipse.equinox.app.IApplicationContext;

// Registers a project directory into the open workspace using the real
// resource APIs, so the project lands in Eclipse's own resource tree (not
// just a hand-written metadata file). Run via:
//   eclipse -nosplash -application cb.importproject.app -data <workspace> <projectDir>
public class Application implements IApplication {
    @Override
    public Object start(IApplicationContext context) throws Exception {
        String[] args = (String[]) context.getArguments().get(IApplicationContext.APPLICATION_ARGS);
        if (args == null || args.length < 1) {
            System.err.println("usage: -application cb.importproject.app <projectDir>");
            return IApplication.EXIT_OK;
        }
        File dir = new File(args[0]).getAbsoluteFile();
        IWorkspace ws = ResourcesPlugin.getWorkspace();
        IProgressMonitor monitor = new NullProgressMonitor();

        File dotProject = new File(dir, ".project");
        IProjectDescription description;
        String name;
        if (dotProject.isFile()) {
            description = ws.loadProjectDescription(new Path(dotProject.getAbsolutePath()));
            name = description.getName();
        } else {
            name = dir.getName();
            description = ws.newProjectDescription(name);
        }
        description.setLocation(new Path(dir.getAbsolutePath()));

        IProject project = ws.getRoot().getProject(name);
        if (!project.exists()) {
            project.create(description, monitor);
        } else {
            project.move(description, IResource.FORCE, monitor);
        }
        if (!project.isOpen()) {
            project.open(IResource.NONE, monitor);
        }
        System.out.println("cb-import-project: registered [" + name + "] at " + dir);
        return IApplication.EXIT_OK;
    }

    @Override
    public void stop() {
    }
}
JAVAEOF

cat > "$WORK/build/plugin.xml" <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<?eclipse version="3.4"?>
<plugin>
   <extension id="app" point="org.eclipse.core.runtime.applications">
      <application cardinality="singleton-global" thread="main" visible="true">
         <run class="cb.importproject.Application"/>
      </application>
   </extension>
</plugin>
XMLEOF

# singleton:=true is required -- without it Eclipse silently ignores the
# bundle's extensions ("not marked as singleton") and the application can
# never be found, even though the bundle itself loads fine.
cat > "$WORK/build/META-INF/MANIFEST.MF" <<'MFEOF'
Manifest-Version: 1.0
Bundle-ManifestVersion: 2
Bundle-Name: CB Import Project
Bundle-SymbolicName: cb.importproject;singleton:=true
Bundle-Version: 1.0.0
Bundle-Vendor: CodingBooth
Require-Bundle: org.eclipse.core.runtime,
 org.eclipse.core.resources,
 org.eclipse.equinox.app,
 org.eclipse.equinox.common
Bundle-RequiredExecutionEnvironment: JavaSE-21
Bundle-ActivationPolicy: lazy
MFEOF

CP=$(ls "$ECLIPSE_DIR"/plugins/org.eclipse.core.resources_*.jar \
        "$ECLIPSE_DIR"/plugins/org.eclipse.core.runtime_*.jar \
        "$ECLIPSE_DIR"/plugins/org.eclipse.core.jobs_*.jar \
        "$ECLIPSE_DIR"/plugins/org.eclipse.equinox.app_*.jar \
        "$ECLIPSE_DIR"/plugins/org.eclipse.equinox.common_*.jar \
        "$ECLIPSE_DIR"/plugins/org.eclipse.osgi_*.jar 2>/dev/null | tr '\n' ':')

if [ -z "$CP" ]; then
  echo "eclipse-import-project: could not find Eclipse's resource/runtime jars -- skipping." >&2
  rm -rf "$WORK"
  exit 0
fi

javac -cp "$CP" -d "$WORK/build" "$WORK/src/cb/importproject/Application.java"

(cd "$WORK/build" && jar cfm cb.importproject_1.0.0.jar META-INF/MANIFEST.MF plugin.xml cb)

mkdir -p "$ECLIPSE_DIR/dropins"
cp "$WORK/build/cb.importproject_1.0.0.jar" "$ECLIPSE_DIR/dropins/"
chown root:root "$ECLIPSE_DIR/dropins/cb.importproject_1.0.0.jar"
chmod 0644 "$ECLIPSE_DIR/dropins/cb.importproject_1.0.0.jar"
rm -rf "$WORK"

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-eclipse-import-project--startup.sh"
mkdir -p /usr/share/startup.d
cat > "$STARTUP_FILE" <<'STARTUPEOF'
#!/usr/bin/env bash
# Eclipse project auto-import: register $CODE_DIR into ~/eclipse-workspace via
# the cb.importproject.app headless Eclipse application (see the setup script
# that installed it), so the project lands in the real resource tree instead
# of a hand-written metadata file. Best-effort -- never fails the boot.

CB_ECLIPSE_PROJECT_DIR="${CODE_DIR:-$HOME/code}"
CB_ECLIPSE_WORKSPACE="$HOME/eclipse-workspace"
CB_ECLIPSE_KIND="__ECLIPSE_KIND__"

if command -v java >/dev/null 2>&1 && command -v eclipse >/dev/null 2>&1 && [ -d "$CB_ECLIPSE_PROJECT_DIR" ]; then
  if [ "$CB_ECLIPSE_KIND" = "DEFAULT" ]; then
    if [ -f "$CB_ECLIPSE_PROJECT_DIR/pom.xml" ]; then
      CB_ECLIPSE_KIND=MAVEN
    elif [ -f "$CB_ECLIPSE_PROJECT_DIR/build.gradle" ] || [ -f "$CB_ECLIPSE_PROJECT_DIR/build.gradle.kts" ] || [ -f "$CB_ECLIPSE_PROJECT_DIR/settings.gradle" ] || [ -f "$CB_ECLIPSE_PROJECT_DIR/settings.gradle.kts" ]; then
      CB_ECLIPSE_KIND=GRADLE
    else
      CB_ECLIPSE_KIND=GENERAL
    fi
  fi

  if [ ! -f "$CB_ECLIPSE_PROJECT_DIR/.project" ]; then
    CB_ECLIPSE_NAME="$(basename "$CB_ECLIPSE_PROJECT_DIR")"
    case "$CB_ECLIPSE_KIND" in
      MAVEN)
        CB_ECLIPSE_NATURES='<nature>org.eclipse.m2e.core.maven2Nature</nature><nature>org.eclipse.jdt.core.javanature</nature>'
        CB_ECLIPSE_BUILDERS='<buildCommand><name>org.eclipse.jdt.core.javabuilder</name><arguments></arguments></buildCommand><buildCommand><name>org.eclipse.m2e.core.maven2Builder</name><arguments></arguments></buildCommand>'
        ;;
      GRADLE)
        CB_ECLIPSE_NATURES='<nature>org.eclipse.buildship.core.gradleprojectnature</nature><nature>org.eclipse.jdt.core.javanature</nature>'
        CB_ECLIPSE_BUILDERS='<buildCommand><name>org.eclipse.jdt.core.javabuilder</name><arguments></arguments></buildCommand><buildCommand><name>org.eclipse.buildship.core.gradleprojectbuilder</name><arguments></arguments></buildCommand>'
        ;;
      *)
        CB_ECLIPSE_NATURES=''
        CB_ECLIPSE_BUILDERS=''
        ;;
    esac
    cat > "$CB_ECLIPSE_PROJECT_DIR/.project" <<PROJECTEOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>${CB_ECLIPSE_NAME}</name>
	<comment></comment>
	<projects></projects>
	<buildSpec>${CB_ECLIPSE_BUILDERS}</buildSpec>
	<natures>${CB_ECLIPSE_NATURES}</natures>
</projectDescription>
PROJECTEOF
  fi

  CB_ECLIPSE_NAME="$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' "$CB_ECLIPSE_PROJECT_DIR/.project" 2>/dev/null | head -n1)"
  [ -n "$CB_ECLIPSE_NAME" ] || CB_ECLIPSE_NAME="$(basename "$CB_ECLIPSE_PROJECT_DIR")"

  CB_ECLIPSE_LOCATION_FILE="$CB_ECLIPSE_WORKSPACE/.metadata/.plugins/org.eclipse.core.resources/.projects/$CB_ECLIPSE_NAME/.location"

  if [ ! -f "$CB_ECLIPSE_LOCATION_FILE" ]; then
    if eclipse -nosplash -application cb.importproject.app -data "$CB_ECLIPSE_WORKSPACE" "$CB_ECLIPSE_PROJECT_DIR" >/tmp/cb-eclipse-import.log 2>&1; then
      echo "Eclipse: registered '$CB_ECLIPSE_NAME' ($CB_ECLIPSE_KIND) into ~/eclipse-workspace"
    else
      echo "Eclipse: could not pre-register '$CB_ECLIPSE_NAME' -- open it manually via File > Import (see /tmp/cb-eclipse-import.log)" >&2
    fi
  fi
fi
STARTUPEOF

sed -i "s/__ECLIPSE_KIND__/${KIND}/" "$STARTUP_FILE"
chmod 0755 "$STARTUP_FILE"

echo "✅ cb.importproject headless app installed at ${ECLIPSE_DIR}/dropins/cb.importproject_1.0.0.jar"
echo "✅ Eclipse project auto-import hook installed at ${STARTUP_FILE} (kind=${KIND})"
