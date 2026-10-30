// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package prepare

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"time"
)

// Options are the command's inputs.
type Options struct {
	Target      Target
	Variant     string // --variant ("" = config.toml's, else base)
	AddUser     string // --add-user (root only)
	Source      string // --source: a CodingBooth checkout instead of the embedded kit
	Report      string // --report: where the provisioning report goes ("" = a temp file)
	Yes         bool   // --yes: no confirmation on ubuntu
	ProjectDir  string
	Interactive bool
	Stdin       io.Reader
	Stdout      io.Writer
	Stderr      io.Writer
}

// Run prepares the machine and returns the exit code: 0 when every phase and
// every report line passed, 1 when something failed (each failure is listed),
// 2 for a usage error.
func Run(o Options) int {
	errf := func(format string, a ...any) int {
		fmt.Fprintf(o.Stderr, "Error: "+format+"\n", a...)
		return 1
	}
	fmt.Fprintf(o.Stderr, "Warning: booth prepare is experimental (docs/REUSE_BOOTH.md). It changes this machine, not a container.\n")

	// 1. The machine must be the kind the target names.
	osRelease, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return errf("cannot read /etc/os-release: %v", err)
	}
	if err := CheckMachine(o.Target, ParseOSRelease(string(osRelease)), os.Getenv); err != nil {
		return errf("%v", err)
	}

	// 2. Who it is for.
	me, err := user.Current()
	if err != nil {
		return errf("cannot tell the current user: %v", err)
	}
	who, err := DecideUser(os.Geteuid(), me.Username, o.AddUser)
	if err != nil {
		return errf("%v", err)
	}

	// 3. The project and its variant.
	project, err := filepath.Abs(o.ProjectDir)
	if err != nil {
		return errf("%v", err)
	}
	if info, err := os.Stat(project); err != nil || !info.IsDir() {
		return errf("%s is not a folder", o.ProjectDir)
	}
	cfg, err := LoadConfig(filepath.Join(project, ".booth", "config.toml"))
	if err != nil {
		return errf("%v", err)
	}
	variant, note, err := ResolveVariant(o.Target, o.Variant, cfg.Variant)
	if err != nil {
		return errf("%v", err)
	}
	configEnv, _ := RunArgsEnv(cfg.RunArgs)

	// 4. Where the scripts come from.
	kitDir := o.Source
	if kitDir != "" {
		if kitDir, err = filepath.Abs(kitDir); err != nil {
			return errf("%v", err)
		}
	} else if !HasKit() {
		return errf("%v", ErrNoKit)
	}

	// 5. Say what will happen; on ubuntu, ask.
	fmt.Fprintf(o.Stdout, "booth prepare %s\n", o.Target)
	fmt.Fprintf(o.Stdout, "  project : %s\n", project)
	fmt.Fprintf(o.Stdout, "  user    : %s%s\n", who.Name, map[bool]string{true: " (created if missing, added to sudo)", false: ""}[who.Create])
	fmt.Fprintf(o.Stdout, "  variant : %s\n", variant)
	if note != "" {
		fmt.Fprintf(o.Stdout, "            %s\n", note)
	}
	if o.Source != "" {
		fmt.Fprintf(o.Stdout, "  scripts : %s\n", kitDir)
	} else {
		fmt.Fprintf(o.Stdout, "  scripts : embedded in this binary\n")
	}
	fmt.Fprintln(o.Stdout, "  changes : apt packages, /opt/codingbooth, /usr/local/bin, /etc/profile.d (every user's login shell),")
	fmt.Fprintln(o.Stdout, "            the project's Boothfile setups (as root), then booth-entry's user steps for", who.Name)
	if o.Target == Ubuntu && !o.Yes {
		if !o.Interactive {
			return errf("booth prepare ubuntu changes this whole machine; run it on a terminal to confirm, or pass --yes")
		}
		fmt.Fprint(o.Stderr, "Prepare this machine? [y/N] ")
		answer, _ := bufio.NewReader(o.Stdin).ReadString('\n')
		if a := strings.TrimSpace(answer); a != "y" && a != "Y" {
			fmt.Fprintln(o.Stderr, "Nothing changed.")
			return 1
		}
	}

	// 6. Root rights: sudo for a user (kept fresh for the whole run), or root itself.
	r := runner{o: o, sudo: who.UseSudo}
	if who.UseSudo {
		if err := ensureSudo(o); err != nil {
			return errf("%v", err)
		}
		stop := keepSudoAlive()
		defer stop()
	}
	if who.Create {
		if err := ensureUser(o, who.Name); err != nil {
			return errf("%v", err)
		}
	}
	target, err := user.Lookup(who.Name)
	if err != nil {
		return errf("user %s: %v", who.Name, err)
	}

	// 7. The kit, unpacked where root and the user can read it.
	if o.Source == "" {
		if kitDir, err = os.MkdirTemp("", "booth-prepare-kit-"); err != nil {
			return errf("%v", err)
		}
		defer os.RemoveAll(kitDir)
		if err := ExtractKit(kitDir); err != nil {
			return errf("%v", err)
		}
		os.Chmod(kitDir, 0755)
	}
	if err := CheckSource(kitDir); err != nil {
		return errf("%v", err)
	}
	scripts := filepath.Join(kitDir, "experiments", "host-provision")

	report := o.Report
	if report == "" {
		dir, err := os.MkdirTemp("", "booth-prepare-")
		if err != nil {
			return errf("%v", err)
		}
		os.Chmod(dir, 0755)
		report = filepath.Join(dir, "report.txt")
	}
	if report, err = filepath.Abs(report); err != nil {
		return errf("%v", err)
	}
	// Root creates the report, as root appends to it: in a sticky folder such as /tmp,
	// fs.protected_regular stops root from opening a file the user owns. 0666 keeps it
	// readable and writable for the user.
	if err := r.root(nil, "rm", "-f", report); err != nil {
		return errf("report %s: %v", report, err)
	}
	if err := r.root(nil, "install", "-m", "0666", "/dev/null", report); err != nil {
		return errf("report %s: %v", report, err)
	}

	common := []string{
		"CB_TARGET=" + o.Target.CBTarget(),
		"CB_USER_NAME=" + target.Username,
		"CB_USER_HOME=" + target.HomeDir,
		"REPORT=" + report,
	}
	failed := []string{}
	phase := func(name string, env []string, argv ...string) bool {
		fmt.Fprintf(o.Stdout, "\n==== booth prepare: %s\n", name)
		if err := r.root(append(common, env...), argv...); err != nil {
			failed = append(failed, fmt.Sprintf("%s: %v", name, err))
			return false
		}
		return true
	}

	// 8. The phases. A failed base phase stops the run; the later ones record each
	// failing line and go on, so one run lists every problem.
	if !phase("base image (variants/base/Dockerfile)", nil, filepath.Join(scripts, "base-provision.sh"), kitDir) {
		return summary(o, report, failed)
	}
	if variant != "base" {
		phase("variant "+variant, nil, filepath.Join(scripts, "provision-variant.sh"), kitDir, variant)
	}
	configEnv = RewriteHome(configEnv, target.HomeDir)
	phase("Boothfile", []string{"CB_PREPARE_VARIANT=" + variant}, filepath.Join(scripts, "provision-example.sh"), project)
	if err := r.writeConfigEnv(o.Target.CBTarget(), configEnv); err != nil {
		failed = append(failed, "config.toml env: "+err.Error())
	}
	entryEnv := []string{"CB_CODE_DIR=" + project, "HOST_UID=" + target.Uid, "HOST_GID=" + target.Gid}
	for _, e := range configEnv {
		entryEnv = append(entryEnv, e.Key+"="+e.Value)
	}
	phase("booth-entry user steps (profile, seeds, startup hooks)", entryEnv, "/usr/local/bin/booth-entry", "true")

	// 9. GHA: later steps run a plain `bash -e`, which reads no profile.
	if o.Target == GHA {
		if err := exportToGitHub(o, target.Username, me.Username); err != nil {
			failed = append(failed, "export to later steps: "+err.Error())
		}
	}
	return summary(o, report, failed)
}

func summary(o Options, report string, failed []string) int {
	data, _ := os.ReadFile(report)
	fails := ReportFailures(string(data))
	var drops []string
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "DROP ") {
			drops = append(drops, line)
		}
	}
	fmt.Fprintf(o.Stdout, "\n==== booth prepare: report (%s)\n", report)
	for _, d := range drops {
		fmt.Fprintln(o.Stdout, "  "+d)
	}
	if len(fails) == 0 && len(failed) == 0 {
		fmt.Fprintln(o.Stdout, "✅ Prepared. Every phase and every Boothfile line passed.")
		return 0
	}
	for _, f := range failed {
		fmt.Fprintln(o.Stderr, "❌ "+f)
	}
	for _, f := range fails {
		fmt.Fprintln(o.Stderr, "❌ "+f)
	}
	fmt.Fprintf(o.Stderr, "booth prepare: %d failure(s). Full log above; report at %s\n", len(fails)+len(failed), report)
	return 1
}

// runner runs root commands: directly as root, else through sudo.
type runner struct {
	o    Options
	sudo bool
}

func (r runner) root(env []string, argv ...string) error {
	var cmd *exec.Cmd
	if r.sudo {
		cmd = exec.Command("sudo", append(append([]string{"env"}, env...), argv...)...)
	} else {
		cmd = exec.Command("env", append(env, argv...)...)
	}
	cmd.Stdin = nil
	cmd.Stdout = r.o.Stdout
	cmd.Stderr = r.o.Stderr
	return cmd.Run()
}

// writeConfigEnv puts CB_TARGET and config.toml's -e KEY=VALUE run-args in a
// profile script, so every later login shell has them, as every process in a
// booth does (ConfigProfile).
func (r runner) writeConfigEnv(cbTarget string, env []EnvVar) error {
	tmp, err := os.CreateTemp("", "cb-config-env-")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	tmp.WriteString(ConfigProfile(cbTarget, env))
	tmp.Close()
	os.Chmod(tmp.Name(), 0644)
	return r.root(nil, "install", "-m", "0644", tmp.Name(), "/etc/profile.d/06-cb-config-env.sh")
}

// ensureSudo checks the user may use sudo: without a password, or after one prompt
// on a terminal.
func ensureSudo(o Options) error {
	if _, err := exec.LookPath("sudo"); err != nil {
		return fmt.Errorf("sudo is not installed; booth prepare needs root rights for apt and /opt")
	}
	if exec.Command("sudo", "-n", "true").Run() == nil {
		return nil
	}
	if !o.Interactive {
		return fmt.Errorf("this user cannot use sudo without a password, and there is no terminal to ask for one; booth prepare needs a user that can sudo")
	}
	fmt.Fprintln(o.Stderr, "booth prepare needs root rights for apt, /opt and /etc; sudo may ask for your password.")
	cmd := exec.Command("sudo", "-v")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, o.Stdout, o.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("this user cannot use sudo (%v); booth prepare needs a user that can sudo", err)
	}
	return nil
}

// keepSudoAlive refreshes sudo's timestamp, so a long run does not stop at a second prompt.
func keepSudoAlive() (stop func()) {
	done := make(chan struct{})
	go func() {
		t := time.NewTicker(60 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				exec.Command("sudo", "-n", "-v").Run()
			}
		}
	}()
	return func() { close(done) }
}

// ensureUser (as root) creates the user when missing and adds it to the sudo group.
func ensureUser(o Options, name string) error {
	if _, err := user.Lookup(name); err != nil {
		fmt.Fprintf(o.Stdout, "Creating user %s\n", name)
		if out, err := exec.Command("useradd", "-m", "-s", "/bin/bash", name).CombinedOutput(); err != nil {
			return fmt.Errorf("useradd %s: %v: %s", name, err, strings.TrimSpace(string(out)))
		}
	} else {
		fmt.Fprintf(o.Stdout, "User %s exists; using it\n", name)
	}
	if out, err := exec.Command("usermod", "-aG", "sudo", name).CombinedOutput(); err != nil {
		return fmt.Errorf("usermod -aG sudo %s: %v: %s", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// exportToGitHub writes what a login shell of the user has, and this step does
// not, to $GITHUB_ENV and $GITHUB_PATH.
func exportToGitHub(o Options, targetUser, currentUser string) error {
	var cmd *exec.Cmd
	if targetUser == currentUser {
		cmd = exec.Command("bash", "-lc", "env -0")
	} else {
		cmd = exec.Command("runuser", "-u", targetUser, "--", "bash", "-lc", "env -0")
	}
	cmd.Dir = o.ProjectDir
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("bash -lc env: %v", err)
	}
	before := map[string]string{}
	for _, kv := range os.Environ() {
		if k, v, ok := strings.Cut(kv, "="); ok {
			before[k] = v
		}
	}
	buf := make([]byte, 12)
	rand.Read(buf)
	envLines, pathLines := GitHubExports(before, ParseEnv0(out), "CB_EOF_"+hex.EncodeToString(buf))
	if err := appendFile(os.Getenv("GITHUB_ENV"), envLines); err != nil {
		return err
	}
	if len(pathLines) > 0 {
		if err := appendFile(os.Getenv("GITHUB_PATH"), strings.Join(pathLines, "\n")+"\n"); err != nil {
			return err
		}
	}
	fmt.Fprintf(o.Stdout, "Exported to later steps: %d variable(s) to GITHUB_ENV, %d PATH entr%s to GITHUB_PATH\n",
		strings.Count(envLines, "<<"), len(pathLines), map[bool]string{true: "y", false: "ies"}[len(pathLines) == 1])
	return nil
}

func appendFile(path, content string) error {
	if content == "" {
		return nil
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(content)
	return err
}
