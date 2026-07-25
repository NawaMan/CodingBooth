# C# Example

This example is a minimal C# console app targeting .NET 9. The bundled `Program.cs` prints a greeting and then computes and prints the sum of the numbers 1 through 10. The point of this example is reproducibility: the .NET SDK channel is pinned, so every person and every CI run builds against the exact same SDK. That kills the classic "works on my machine" gap where one teammate's newer SDK silently changes build behavior or restores different package versions. Everyone gets byte-for-byte the same toolchain — and when you do want to move, you change the `DOTNET_CHANNEL` build arg once and the whole team moves together, deliberately rather than by accident.

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
