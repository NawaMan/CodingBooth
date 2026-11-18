// Playwright, the Java way (com.microsoft.playwright). Open a real page, screenshot it,
// print TITLE|SUM.
import java.nio.file.Paths;

import com.microsoft.playwright.Browser;
import com.microsoft.playwright.Page;
import com.microsoft.playwright.Playwright;
import com.microsoft.playwright.options.WaitUntilState;

public class Check {
    public static void main(String[] args) {
        String url = System.getenv().getOrDefault("PAGE_URL", "https://www.java.com/en/");
        String shot = System.getenv().getOrDefault("SHOT_PATH", "java.png");

        try (Playwright pw = Playwright.create()) {
            Browser browser = pw.chromium().launch();
            Page page = browser.newPage(new Browser.NewPageOptions()
                    .setViewportSize(1280, 800));
            page.navigate(url, new Page.NavigateOptions()
                    .setWaitUntil(WaitUntilState.DOMCONTENTLOADED)
                    .setTimeout(60000));
            page.waitForTimeout(3000);
            Object sum = page.evaluate(
                    "() => { let s = 0; for (let i = 1; i <= 10; i++) s += i; return s; }");
            String title = page.title();
            page.screenshot(new Page.ScreenshotOptions().setPath(Paths.get(shot)));
            System.out.println(title + "|" + sum);
            browser.close();
        }
    }
}
