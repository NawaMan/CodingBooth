#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

cd /home/coder/code

echo "=== bash-3.2 version, use-bash, count-args, empty-array rejection ==="
ver="$(bash-3.2 --version | head -1)"
echo "$ver"
echo "$ver" | grep -q "3.2.57" || { echo "expected 3.2.57, got: $ver"; exit 1; }

sys="$(bash --version | head -1)"
echo "login bash: $sys"
echo "$sys" | grep -q "3.2.57" && { echo "/bin/bash should stay the distro bash"; exit 1; }

# count-args.sh is #!/bin/bash. use-bash runs it on 3.2 without editing it.
zero="$(use-bash 3.2 ./scripts/count-args.sh)"
echo "$zero"
[[ "$zero" == "count=0" ]] || { echo "expected count=0, got: $zero"; exit 1; }

two="$(use-bash 3.2 ./scripts/count-args.sh one two)"
echo "$two"
[[ "$two" == "count=2" ]] || { echo "expected count=2, got: $two"; exit 1; }

distro="$(./scripts/count-args.sh)"
[[ "$distro" == "count=0" ]] || { echo "expected count=0 on the distro bash, got: $distro"; exit 1; }

# A #!/bin/bash script calling another: both run on 3.2 under use-bash.
printf '#!/bin/bash\necho "$BASH_VERSION"\n' > /tmp/bash-child.sh
printf '#!/bin/bash\n/tmp/bash-child.sh\n' > /tmp/bash-parent.sh
chmod +x /tmp/bash-child.sh /tmp/bash-parent.sh
nested="$(use-bash 3.2 /tmp/bash-parent.sh)"
echo "nested child: $nested"
[[ "$nested" == 3.2.* ]] || { echo "nested #!/bin/bash should be 3.2, got: $nested"; exit 1; }
plain="$(/tmp/bash-parent.sh)"
[[ "$plain" != 3.2.* ]] || { echo "without use-bash the child should be the distro bash"; exit 1; }

# scripts/which-bash.sh: a tree of #!/bin/bash and env-bash scripts, plus
# bash -c. Each line reports its bash and whether declare -A works.
tree="$(./scripts/which-bash.sh)"
echo "$tree"
bash_lines="$(echo "$tree" | grep -c 'declare -A:')"
[[ "$bash_lines" == 7 ]] || { echo "expected 7 bash levels, got $bash_lines"; exit 1; }
echo "$tree" | grep -q '3\.2\.' && { echo "no level should be 3.2 without use-bash"; exit 1; }
[[ "$(echo "$tree" | grep -c 'declare -A: yes')" == 7 ]] || { echo "every level should have declare -A on the distro bash"; exit 1; }

tree="$(use-bash 3.2 ./scripts/which-bash.sh)"
echo "$tree"
[[ "$(echo "$tree" | grep -c ' 3\.2\.57.*declare -A: no')" == 7 ]] || { echo "every level should be 3.2 without declare -A under use-bash"; exit 1; }
echo "$tree" | grep -q 'sh -c.*dash' || { echo "sh -c should stay on dash"; exit 1; }

# A version with no setup-bash release falls back to the image's own bash
# when its version matches by whole components; one that matches nothing fails.
distro_ver="$(/usr/bin/bash.distro -c 'printf %s "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
got="$(use-bash "$distro_ver" bash -c 'printf %s "$BASH_VERSION"')"
echo "use-bash $distro_ver: $got"
[[ "$got" == "$distro_ver".* ]] || { echo "use-bash $distro_ver should reach the distro bash, got: $got"; exit 1; }
if use-bash 9.9 true 2>/dev/null; then echo "use-bash 9.9 should fail"; exit 1; fi
if use-bash 3.2.5 true 2>/dev/null; then echo "use-bash 3.2.5 should not match 3.2.57"; exit 1; fi

cat > /tmp/bash-unsafe.sh <<'EOF'
#!/bin/bash
set -u
a=()
echo "${a[@]}"
echo survived
EOF
chmod +x /tmp/bash-unsafe.sh
if use-bash 3.2 /tmp/bash-unsafe.sh > /tmp/bash-unsafe.out 2> /tmp/bash-unsafe.err; then
    echo "empty array under set -u should fail on bash 3.2"
    exit 1
fi
if grep -q survived /tmp/bash-unsafe.out; then
    echo "unsafe script should exit before printing survived"
    exit 1
fi
grep -q "unbound variable" /tmp/bash-unsafe.err
echo "ok"
