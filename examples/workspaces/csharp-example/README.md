# C# Example

A minimal C# console app on .NET 9.

**Stack:** .NET SDK 9.0, C#

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/csharp-example
booth

# 2. Inside the booth — build and run
./run-csharp.sh
```

## What's included

| Component        | Details                                |
|------------------|----------------------------------------|
| Runtime / SDK    | .NET 9.0                               |
| VS Code support  | C# Dev Kit extension                   |
| Sample           | `Program.cs`, `csharp-example.csproj`  |

Override the .NET channel via the `DOTNET_CHANNEL` build arg in `.booth/Boothfile`.
