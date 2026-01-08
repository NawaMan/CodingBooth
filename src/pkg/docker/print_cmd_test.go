package docker

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"testing"
)

// TestPrintCmd_SimpleArgs verifies simple arguments are printed without quotes.
func TestPrintCmd_SimpleArgs(t *testing.T) {
	tests := []struct {
		name     string
		command  string
		args     [][]string
		expected string
	}{
		{
			name:     "simple command",
			command:  "docker",
			args:     [][]string{{"version"}},
			expected: "docker \\\n    version\n",
		},
		{
			name:     "alphanumeric args",
			command:  "docker",
			args:     [][]string{{"run", "ubuntu:20.04"}},
			expected: "docker \\\n    run ubuntu:20.04\n",
		},
		{
			name:     "args with allowed special chars",
			command:  "docker",
			args:     [][]string{{"build", "-t", "my-image:1.0", "/path/to/dir"}},
			expected: "docker \\\n    build -t my-image:1.0 /path/to/dir\n",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Capture stdout
			oldStdout := os.Stdout
			reader, writer, _ := os.Pipe()
			os.Stdout = writer

			printCmd(test.command, test.args...)

			// Restore stdout
			writer.Close()
			os.Stdout = oldStdout

			// Read captured output
			var buf bytes.Buffer
			io.Copy(&buf, reader)
			output := buf.String()

			if output != test.expected {
				t.Errorf("PrintCmd() = %q, want %q", output, test.expected)
			}
		})
	}
}

// TestPrintCmd_ComplexArgs verifies complex arguments are properly quoted.
func TestPrintCmd_ComplexArgs(t *testing.T) {
	tests := []struct {
		name     string
		command  string
		args     [][]string
		expected string
	}{
		{
			name:     "arg with spaces",
			command:  "docker",
			args:     [][]string{{"run", "-e", "VAR=hello world"}},
			expected: "docker \\\n    run -e 'VAR=hello world'\n",
		},
		{
			name:     "arg with single quote",
			command:  "docker",
			args:     [][]string{{"run", "-e", "VAR=it's"}},
			expected: "docker \\\n    run -e 'VAR=it'\\''s'\n",
		},
		{
			name:     "arg with multiple single quotes",
			command:  "docker",
			args:     [][]string{{"echo", "don't say 'hello'"}},
			expected: "docker \\\n    echo 'don'\\''t say '\\''hello'\\'''\n",
		},
		{
			name:     "arg with special chars",
			command:  "bash",
			args:     [][]string{{"-c", "echo $HOME"}},
			expected: "bash \\\n    -c 'echo $HOME'\n",
		},
		{
			name:     "empty arg",
			command:  "docker",
			args:     [][]string{{"run", ""}},
			expected: "docker \\\n    run ''\n",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Capture stdout
			oldStdout := os.Stdout
			reader, writer, _ := os.Pipe()
			os.Stdout = writer

			printCmd(test.command, test.args...)

			// Restore stdout
			writer.Close()
			os.Stdout = oldStdout

			// Read captured output
			var buf bytes.Buffer
			io.Copy(&buf, reader)
			output := buf.String()

			if output != test.expected {
				t.Errorf("PrintCmd() = %q, want %q", output, test.expected)
			}
		})
	}
}

// TestPrintCmd_RealWorldExamples verifies real-world usage patterns.
func TestPrintCmd_RealWorldExamples(t *testing.T) {
	tests := []struct {
		name     string
		command  string
		args     [][]string
		expected string
	}{
		{
			name:    "docker build",
			command: "docker",
			args: [][]string{
				{"build"},
				{"-f", "Dockerfile"},
				{"-t", "workspace-local:myproject-default-latest"},
				{"--build-arg", "WS_VARIANT_TAG=default"},
				{"/workspace"},
			},
			expected: "docker \\\n    build \\\n    -f Dockerfile \\\n    -t workspace-local:myproject-default-latest \\\n    --build-arg 'WS_VARIANT_TAG=default' \\\n    /workspace\n",
		},
		{
			name:    "docker run with bash command",
			command: "docker",
			args: [][]string{
				{"run", "-it"},
				{"--rm", "ubuntu"},
				{"bash", "-lc", "echo 'Hello World'"},
			},
			expected: "docker \\\n    run -it \\\n    --rm ubuntu \\\n    bash -lc 'echo '\\''Hello World'\\'''\n",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Capture stdout
			oldStdout := os.Stdout
			reader, writer, _ := os.Pipe()
			os.Stdout = writer

			printCmd(test.command, test.args...)

			// Restore stdout
			writer.Close()
			os.Stdout = oldStdout

			// Read captured output
			var buf bytes.Buffer
			io.Copy(&buf, reader)
			output := buf.String()

			if output != test.expected {
				t.Errorf("PrintCmd() output mismatch:\ngot:  %q\nwant: %q", output, test.expected)
			}
		})
	}
}

// TestPrintCmd_OutputFormat verifies PrintCmd output format.
// Each argument is followed by a space, and output ends with a newline.
func TestPrintCmd_OutputFormat(t *testing.T) {
	tests := []struct {
		name     string
		command  string
		args     [][]string
		expected string
	}{
		{
			name:     "Test 1: Simple command",
			command:  "echo",
			args:     [][]string{{"hello"}},
			expected: "echo \\\n    hello\n",
		},
		{
			name:     "Test 2: Command with spaces needs quoting",
			command:  "echo",
			args:     [][]string{{"hello world"}},
			expected: "echo \\\n    'hello world'\n",
		},
		{
			name:     "Test 3: Command with single quotes",
			command:  "echo",
			args:     [][]string{{"it's"}},
			expected: "echo \\\n    'it'\\''s'\n",
		},
		{
			name:     "Test 4: Multiple simple args",
			command:  "docker",
			args:     [][]string{{"run", "-it", "ubuntu"}},
			expected: "docker \\\n    run -it ubuntu\n",
		},
		{
			name:     "Test 5: Args with paths",
			command:  "/usr/bin/docker",
			args:     [][]string{{"/path/to/file"}},
			expected: "/usr/bin/docker \\\n    /path/to/file\n",
		},
		{
			name:     "Test 6: Args with special characters",
			command:  "echo",
			args:     [][]string{{"hello$world"}},
			expected: "echo \\\n    'hello$world'\n",
		},
		{
			name:     "Test 8: Command with equals sign (gets quoted)",
			command:  "--env=VALUE",
			args:     [][]string{{}},
			expected: "'--env=VALUE'\n",
		},
		{
			name:     "Test 9: Command with colons",
			command:  "image:tag",
			args:     [][]string{{}},
			expected: "image:tag\n",
		},
		{
			name:     "Test 10: Mixed simple and complex args",
			command:  "docker",
			args:     [][]string{{"run"}, {"my image"}, {"--name=test"}},
			expected: "docker \\\n    run \\\n    'my image' \\\n    '--name=test'\n",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Capture stdout
			oldStdout := os.Stdout
			reader, writer, _ := os.Pipe()
			os.Stdout = writer

			printCmd(test.command, test.args...)

			// Restore stdout
			writer.Close()
			os.Stdout = oldStdout

			// Read captured output
			var buf bytes.Buffer
			io.Copy(&buf, reader)
			output := buf.String()

			if output != test.expected {
				t.Errorf("PrintCmd() = %q, want %q", output, test.expected)
			}
		})
	}
}

// TestEscapeArg verifies the shell escaping logic.
func TestEscapeArg(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello", "'hello'"},
		{"hello world", "'hello world'"},
		{"it's", "'it'\\''s'"},
		{"don't", "'don'\\''t'"},
		{"'quoted'", "''\\''quoted'\\'''"},
		{"", "''"},
		{"$VAR", "'$VAR'"},
		{"a'b'c", "'a'\\''b'\\''c'"},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("escape_%s", test.input), func(t *testing.T) {
			result := escapeArg(test.input)
			if result != test.expected {
				t.Errorf("escapeArg(%q) = %q, want %q", test.input, result, test.expected)
			}
		})
	}
}
