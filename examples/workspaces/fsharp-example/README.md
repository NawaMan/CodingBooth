# F# Example

A minimal F# console app on .NET 9.

**Stack:** .NET SDK 9.0, F#

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/fsharp-example
booth

# 2. Inside the booth — build and run
./run-fsharp.sh
```

## What's included

| Component        | Details                                  |
|------------------|------------------------------------------|
| Runtime / SDK    | .NET 9.0                                 |
| VS Code support  | C# Dev Kit (provides F# language server) |
| Sample           | `Program.fs`, `fsharp-example.fsproj`    |

Override the .NET channel via the `DOTNET_CHANNEL` build arg in `.booth/Boothfile`.
