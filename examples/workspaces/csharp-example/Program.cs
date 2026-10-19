using System;
using System.Linq;

Console.WriteLine("Hello from C# in CodingBooth!");

int upper = 10; // default

if (args.Length > 0 && int.TryParse(args[0], out int parsed) && parsed > 0)
{
    upper = parsed;
}

long sum = Enumerable.Range(1, upper).Sum(i => (long)i);
Console.WriteLine($"Sum of 1..{upper} = {sum}");
