// Playwright, the C#/.NET way (Microsoft.Playwright). Open a real page, screenshot it,
// print TITLE|SUM.
using System;
using System.Threading.Tasks;
using Microsoft.Playwright;

class Program
{
    static async Task Main()
    {
        var url = Environment.GetEnvironmentVariable("PAGE_URL")
                  ?? "https://dotnet.microsoft.com/en-us/languages/csharp";
        var shot = Environment.GetEnvironmentVariable("SHOT_PATH") ?? "csharp.png";

        using var pw = await Playwright.CreateAsync();
        await using var browser = await pw.Chromium.LaunchAsync();
        var page = await browser.NewPageAsync(new BrowserNewPageOptions
        {
            ViewportSize = new ViewportSize { Width = 1280, Height = 800 }
        });
        await page.GotoAsync(url, new PageGotoOptions
        {
            WaitUntil = WaitUntilState.DOMContentLoaded,
            Timeout = 60000
        });
        await page.WaitForTimeoutAsync(3000);
        var sum = await page.EvaluateAsync<int>(
            "() => { let s = 0; for (let i = 1; i <= 10; i++) s += i; return s; }");
        var title = await page.TitleAsync();
        await page.ScreenshotAsync(new PageScreenshotOptions { Path = shot });
        Console.WriteLine($"{title}|{sum}");
    }
}
