// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"archive/tar"
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// logDir is where a booth's services write their logs: built-in startup hooks
// to startups.log, autostarted services to <service>.log or <service>-*.log.
const logDir = "/tmp"

// startupLogService is the name `booth logs --startup` reads: /tmp/startups.log,
// where booth-entry sends the stdout of the image's startup hooks.
const startupLogService = "startups"

// logFile is one log in a booth's logDir.
type logFile struct {
	Path    string // absolute path inside the booth, e.g. /tmp/excalidraw.log
	Size    int64
	ModTime time.Time
	Content []byte // only read from a stopped booth, where nothing can be tailed live
}

// Service is the name `booth logs <name>` takes for this file.
func (f logFile) Service() string {
	return strings.TrimSuffix(path.Base(f.Path), ".log")
}

// serviceNamePattern keeps a service name a plain file-name stem: no path
// separators, so a name can only ever select a file directly in logDir.
var serviceNamePattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9._-]*$`)

// logsOptions is a parsed `booth logs` command line.
type logsOptions struct {
	name     string
	code     string
	follow   bool
	tail     string // "" (everything), "all", or a line count
	since    string
	until    string
	stamps   bool
	list     bool
	services []string
}

// logsValueFlags are the flags that take a separate value, so the positional
// scan can step over it. Flags may appear before or after service names.
var logsValueFlags = map[string]bool{
	"-name": true, "--name": true, "-code": true, "--code": true,
	"-tail": true, "--tail": true, "-n": true,
	"-since": true, "--since": true, "-until": true, "--until": true,
}

// parseLogsArgs parses `booth logs` arguments. Positional arguments are
// service names, not a booth name — the booth is chosen with --name or --code,
// or defaults to the current folder's. Pure for unit tests.
func parseLogsArgs(args []string, stderr io.Writer) (logsOptions, error) {
	var positional, flags []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--" {
			positional = append(positional, args[i+1:]...)
			break
		}
		if strings.HasPrefix(arg, "-") {
			flags = append(flags, arg)
			if !strings.Contains(arg, "=") && logsValueFlags[arg] && i+1 < len(args) {
				i++
				flags = append(flags, args[i])
			}
			continue
		}
		positional = append(positional, arg)
	}

	var opts logsOptions
	var startup bool
	flagSet := flag.NewFlagSet("logs", flag.ContinueOnError)
	flagSet.StringVar(&opts.name, "name", "", "Booth name")
	flagSet.StringVar(&opts.code, "code", "", "Code path used to find the booth")
	flagSet.BoolVar(&opts.follow, "follow", false, "Follow the output")
	flagSet.BoolVar(&opts.follow, "f", false, "Follow the output")
	flagSet.StringVar(&opts.tail, "tail", "", "Number of lines to show from the end (default: all)")
	flagSet.StringVar(&opts.tail, "n", "", "Number of lines to show from the end (default: all)")
	flagSet.StringVar(&opts.since, "since", "", "Container output only: show output since a timestamp or relative time (e.g. 10m)")
	flagSet.StringVar(&opts.until, "until", "", "Container output only: show output before a timestamp or relative time")
	flagSet.BoolVar(&opts.stamps, "timestamps", false, "Container output only: show timestamps")
	flagSet.BoolVar(&opts.stamps, "t", false, "Container output only: show timestamps")
	flagSet.BoolVar(&startup, "startup", false, "Show the startup-hook log ("+logDir+"/"+startupLogService+".log)")
	flagSet.BoolVar(&opts.list, "list", false, "List the log files in the booth's "+logDir)
	flagSet.SetOutput(stderr)
	if err := flagSet.Parse(flags); err != nil {
		return logsOptions{}, commandExit(2, "")
	}

	if startup {
		opts.services = append(opts.services, startupLogService)
	}
	for _, service := range positional {
		service = strings.TrimSuffix(service, ".log")
		if !serviceNamePattern.MatchString(service) {
			return logsOptions{}, commandExit(1, fmt.Sprintf("Error: invalid service name %q. Use 'booth logs --list' to see the names.", service))
		}
		opts.services = append(opts.services, service)
	}

	if opts.tail != "" && opts.tail != "all" {
		if n, err := strconv.Atoi(opts.tail); err != nil || n < 0 {
			return logsOptions{}, commandExit(1, fmt.Sprintf("Error: --tail must be a non-negative number or \"all\", not %q.", opts.tail))
		}
	}
	if opts.list && (len(opts.services) > 0 || opts.follow || opts.tail != "") {
		return logsOptions{}, commandExit(1, "Error: --list takes no service names, --startup, --follow or --tail.")
	}
	if (opts.list || len(opts.services) > 0) && (opts.since != "" || opts.until != "" || opts.stamps) {
		return logsOptions{}, commandExit(1, "Error: --since, --until and --timestamps apply to the container output only, not to log files.")
	}
	return opts, nil
}

// Logs shows a booth's output. With no service names it is `<engine> logs`
// for the booth: what its main process and startup scripts printed. With
// service names (or --startup) it shows those log files from the booth's
// /tmp; --list lists them. `lifecycle` is the one service read from the host
// (see logs_lifecycle.go).
func Logs(args []string, stdout io.Writer, stderr io.Writer) error {
	opts, err := parseLogsArgs(args, stderr)
	if err != nil {
		return err
	}
	if lifecycle, err := wantsLifecycleLog(opts); err != nil {
		return err
	} else if lifecycle {
		return showLifecycleLog(opts, stdout, stderr)
	}

	containers, err := managedContainersAcross(resolveLifecycleEngines(opts.code), false, stderr)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}
	target, err := resolveSingleContainer(containers, opts.name, opts.code, nil, stateAny)
	if err != nil {
		return commandExit(1, err.Error())
	}

	if !opts.list && len(opts.services) == 0 {
		if err := docker.Docker(docker.DockerFlags{Engine: target.Engine}, "logs", ilist.NewList(containerLogsArgs(opts, target.Name)...)); err != nil {
			return forwardExitCode("read the logs of", target.Name, err)
		}
		return nil
	}

	files, err := boothLogFiles(target)
	if err != nil {
		return err
	}
	if opts.list {
		if entry, found := lifecycleLogEntry(target.CodePath); found {
			files = append(files, entry)
		}
		printLogList(stdout, target.Name, files)
		return nil
	}

	selected, err := selectLogFiles(opts.services, files)
	if err != nil {
		return commandExit(1, err.Error())
	}
	if target.State != "running" {
		writeTail(stdout, selected, opts.tail)
		return nil
	}

	paths := make([]string, 0, len(selected))
	for _, file := range selected {
		paths = append(paths, file.Path)
	}
	execArgs := logTailExecArgs(target.Name, paths, opts)
	if opts.follow {
		if err := followInBooth(target.Engine, execArgs, stdout, stderr); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				return commandExit(exitErr.ExitCode(), "")
			}
			return commandExit(1, fmt.Sprintf("Error: failed to follow the logs of %q: %v", target.Name, err))
		}
		return nil
	}
	if err := docker.Docker(docker.DockerFlags{Engine: target.Engine}, "exec", ilist.NewList(execArgs...)); err != nil {
		return forwardExitCode("read the logs of", target.Name, err)
	}
	return nil
}

// containerLogsArgs is the argument list of `<engine> logs` for opts. Pure for
// unit tests.
func containerLogsArgs(opts logsOptions, name string) []ilist.List[string] {
	var args []ilist.List[string]
	if opts.follow {
		args = append(args, ilist.NewList("--follow"))
	}
	if opts.tail != "" {
		args = append(args, ilist.NewList("--tail", opts.tail))
	}
	if opts.since != "" {
		args = append(args, ilist.NewList("--since", opts.since))
	}
	if opts.until != "" {
		args = append(args, ilist.NewList("--until", opts.until))
	}
	if opts.stamps {
		args = append(args, ilist.NewList("--timestamps"))
	}
	return append(args, ilist.NewList(name))
}

// followWatchdog runs tail in the background and kills it once stdin closes.
// `booth logs -f` holds that stdin open for as long as it runs, so however the
// client goes away — Ctrl+C, a closed pipe, a killed terminal — the engine
// closes it and tail goes too, instead of following on in the booth forever.
const followWatchdog = `"$@" & tail_pid=$!; cat >/dev/null; kill "$tail_pid" 2>/dev/null`

// logTailExecArgs is the `<engine> exec` argument list that tails paths in a
// running booth. Root reads every service's log whoever wrote it. Several files
// get tail's own `==> file <==` headers. Following goes through followWatchdog,
// with -i for the stdin it watches. Pure for unit tests.
func logTailExecArgs(name string, paths []string, opts logsOptions) []ilist.List[string] {
	var args []ilist.List[string]
	if opts.follow {
		args = append(args, ilist.NewList("-i"))
	}
	args = append(args, ilist.NewList("-u", "root"), ilist.NewList(name))
	if opts.follow {
		args = append(args, ilist.NewList("sh", "-c", followWatchdog, "booth-logs"))
	}

	lines := "+1"
	if opts.tail != "" && opts.tail != "all" {
		lines = opts.tail
	}
	tail := []string{"tail", "-n", lines}
	if opts.follow {
		tail = append(tail, "-F")
	}
	args = append(args, ilist.NewList(tail...))
	return append(args, ilist.NewList(paths...))
}

// followInBooth runs a following exec with stdin a pipe this process holds
// open and never writes: it closes only when this process exits, which is
// what followWatchdog waits for. The user's own stdin cannot serve — it may
// be /dev/null, which would stop tail at once.
func followInBooth(engine string, execArgs []ilist.List[string], stdout, stderr io.Writer) error {
	argv := []string{"exec"}
	for _, group := range execArgs {
		argv = append(argv, group.Slice()...)
	}
	cmd := exec.Command(docker.EngineBinary(engine), argv...)
	keepOpen, holder, err := os.Pipe()
	if err != nil {
		return err
	}
	defer holder.Close()
	cmd.Stdin = keepOpen
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	err = cmd.Run()
	_ = keepOpen.Close()
	return err
}

// selectLogFiles maps service names to log files: <name>.log when it exists,
// otherwise every <name>-*.log (penpot → penpot-backend.log, penpot-exporter.log,
// …). Order follows the names; duplicates are dropped. Pure for unit tests.
func selectLogFiles(services []string, files []logFile) ([]logFile, error) {
	byService := map[string]logFile{}
	for _, file := range files {
		byService[file.Service()] = file
	}

	var selected []logFile
	seen := map[string]bool{}
	add := func(file logFile) {
		if !seen[file.Path] {
			seen[file.Path] = true
			selected = append(selected, file)
		}
	}
	var missing []string
	for _, service := range services {
		if file, found := byService[service]; found {
			add(file)
			continue
		}
		matched := false
		for _, file := range files {
			if strings.HasPrefix(file.Service(), service+"-") {
				add(file)
				matched = true
			}
		}
		if !matched {
			missing = append(missing, service)
		}
	}
	if len(missing) == 0 {
		return selected, nil
	}

	names := make([]string, 0, len(files))
	for _, file := range files {
		names = append(names, file.Service())
	}
	available := "none"
	if len(names) > 0 {
		available = strings.Join(names, ", ")
	}
	return nil, fmt.Errorf("Error: no log for %s in the booth's %s (available: %s).", quoteJoin(missing), logDir, available)
}

func quoteJoin(values []string) string {
	quoted := make([]string, 0, len(values))
	for _, value := range values {
		quoted = append(quoted, strconv.Quote(value))
	}
	return strings.Join(quoted, ", ")
}

// boothLogFiles lists the *.log files directly in a booth's logDir, sorted by
// name. A running booth is asked through exec; a stopped one is read with
// `<engine> cp`, which works on a stopped container, so its files carry their
// content.
func boothLogFiles(target managedContainer) ([]logFile, error) {
	if target.State == "running" {
		return runningBoothLogFiles(target)
	}
	if target.Engine == docker.EngineApple {
		return nil, commandExit(1, fmt.Sprintf("Error: booth %q is not running. Reading log files from a stopped booth is not supported on engine apple; start it first.", target.Name))
	}
	return stoppedBoothLogFiles(target)
}

// logListScript prints "<size> <mtime> <path>" per log file, one per line.
const logListScript = `for f in ` + logDir + `/*.log; do [ -f "$f" ] && stat -c '%s %Y %n' "$f"; done; true`

func runningBoothLogFiles(target managedContainer) ([]logFile, error) {
	out, err := docker.DockerOutput(docker.DockerFlags{Engine: target.Engine}, "exec", ilist.NewList(
		ilist.NewList("-u", "root"),
		ilist.NewList(target.Name),
		ilist.NewList("sh", "-c", logListScript),
	))
	if err != nil {
		return nil, commandExit(1, fmt.Sprintf("Error: failed to list the log files of %q: %v", target.Name, err))
	}
	return parseLogList(out), nil
}

// parseLogList reads logListScript's output. Pure for unit tests.
func parseLogList(out string) []logFile {
	var files []logFile
	for _, line := range nonEmptyLines(out) {
		fields := strings.SplitN(line, " ", 3)
		if len(fields) != 3 {
			continue
		}
		size, sizeErr := strconv.ParseInt(fields[0], 10, 64)
		mtime, timeErr := strconv.ParseInt(fields[1], 10, 64)
		if sizeErr != nil || timeErr != nil {
			continue
		}
		files = append(files, logFile{Path: fields[2], Size: size, ModTime: time.Unix(mtime, 0)})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	return files
}

// stoppedBoothLogFiles streams the booth's logDir out as a tar archive and
// keeps its top-level *.log files. Streamed, not buffered: /tmp can hold far
// more than the logs.
func stoppedBoothLogFiles(target managedContainer) ([]logFile, error) {
	cmd := exec.Command(docker.EngineBinary(target.Engine), "cp", target.Name+":"+logDir, "-")
	var cmdErr bytes.Buffer
	cmd.Stderr = &cmdErr
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, commandExit(1, fmt.Sprintf("Error: failed to read the log files of %q: %v", target.Name, err))
	}
	files, readErr := readLogTar(pipe)
	_, _ = io.Copy(io.Discard, pipe)
	if err := cmd.Wait(); err != nil {
		return nil, commandExit(1, fmt.Sprintf("Error: failed to read the log files of %q: %s", target.Name, nonEmpty(strings.TrimSpace(cmdErr.String()), err.Error())))
	}
	if readErr != nil {
		return nil, commandExit(1, fmt.Sprintf("Error: failed to read the log files of %q: %v", target.Name, readErr))
	}
	return files, nil
}

// readLogTar picks the *.log files directly under the archive's top directory
// (`cp <name>:/tmp -` names them tmp/<file>). Pure for unit tests.
func readLogTar(reader io.Reader) ([]logFile, error) {
	var files []logFile
	archive := tar.NewReader(reader)
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
		parts := strings.Split(strings.Trim(header.Name, "/"), "/")
		if header.Typeflag != tar.TypeReg || len(parts) != 2 || !strings.HasSuffix(parts[1], ".log") {
			continue
		}
		content, err := io.ReadAll(archive)
		if err != nil {
			return nil, err
		}
		files = append(files, logFile{Path: logDir + "/" + parts[1], Size: header.Size, ModTime: header.ModTime, Content: content})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	return files, nil
}

// writeTail prints files read from a stopped booth the way `tail -n` prints
// them: the last lines lines of each (all when ""/"all"), with a
// `==> path <==` header per file when there is more than one. Pure for unit
// tests.
func writeTail(out io.Writer, files []logFile, lines string) {
	for i, file := range files {
		if len(files) > 1 {
			if i > 0 {
				_, _ = fmt.Fprintln(out)
			}
			_, _ = fmt.Fprintf(out, "==> %s <==\n", file.Path)
		}
		_, _ = out.Write(lastLines(file.Content, lines))
	}
}

// lastLines is the last n lines of content (all when lines is ""/"all").
func lastLines(content []byte, lines string) []byte {
	n, err := strconv.Atoi(lines)
	if err != nil {
		return content
	}
	if n == 0 {
		return nil
	}
	end := len(content)
	if end > 0 && content[end-1] == '\n' {
		end--
	}
	for i := end - 1; i >= 0; i-- {
		if content[i] == '\n' {
			n--
			if n == 0 {
				return content[i+1:]
			}
		}
	}
	return content
}

// printLogList is the table `booth logs --list` prints.
func printLogList(out io.Writer, name string, files []logFile) {
	if len(files) == 0 {
		_, _ = fmt.Fprintf(out, "No log files in %s of booth %q.\n", logDir, name)
		return
	}
	writer := tabwriter.NewWriter(out, 0, 0, 2, ' ', 0)
	_, _ = fmt.Fprintln(writer, "SERVICE\tSIZE\tMODIFIED\tFILE")
	for _, file := range files {
		_, _ = fmt.Fprintf(writer, "%s\t%s\t%s\t%s\n", file.Service(), humanSize(file.Size), file.ModTime.Local().Format("2006-01-02 15:04:05"), file.Path)
	}
	_ = writer.Flush()
	_, _ = fmt.Fprintln(out)
	_, _ = fmt.Fprintln(out, "Show one with: booth logs <SERVICE>   (add -f to follow)")
}

func humanSize(size int64) string {
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%dB", size)
	}
	value, suffix := float64(size)/unit, "K"
	for _, next := range []string{"M", "G", "T"} {
		if value < unit {
			break
		}
		value, suffix = value/unit, next
	}
	return fmt.Sprintf("%.1f%s", value, suffix)
}
