// Playwright, the Go way (community binding playwright-community/playwright-go).
// Open a real page, screenshot it, print TITLE|SUM. Unlike the four official bindings,
// playwright-go pins its own driver version, so it installs its own browser on first run
// rather than sharing the pre-baked one.
package main

import (
	"fmt"
	"os"

	// The project lives at github.com/playwright-community/playwright-go, but its
	// module path is still the original author's, so that's what we import (the
	// package itself is named "playwright").
	playwright "github.com/mxschmitt/playwright-go"
)

func main() {
	url := getenv("PAGE_URL", "https://go.dev/")
	shot := getenv("SHOT_PATH", "go.png")

	// Fetch the driver + chromium for this binding's pinned version (idempotent).
	if err := playwright.Install(&playwright.RunOptions{Browsers: []string{"chromium"}}); err != nil {
		panic(err)
	}

	pw, err := playwright.Run()
	if err != nil {
		panic(err)
	}
	browser, err := pw.Chromium.Launch()
	if err != nil {
		panic(err)
	}
	page, err := browser.NewPage(playwright.BrowserNewPageOptions{
		Viewport: &playwright.Size{Width: 1280, Height: 800},
	})
	if err != nil {
		panic(err)
	}
	if _, err = page.Goto(url, playwright.PageGotoOptions{
		WaitUntil: playwright.WaitUntilStateDomcontentloaded,
		Timeout:   playwright.Float(60000),
	}); err != nil {
		panic(err)
	}
	page.WaitForTimeout(3000)
	sum, err := page.Evaluate("() => { let s = 0; for (let i = 1; i <= 10; i++) s += i; return s; }")
	if err != nil {
		panic(err)
	}
	title, err := page.Title()
	if err != nil {
		panic(err)
	}
	if _, err = page.Screenshot(playwright.PageScreenshotOptions{
		Path: playwright.String(shot),
	}); err != nil {
		panic(err)
	}
	fmt.Printf("%s|%v\n", title, sum)

	_ = browser.Close()
	_ = pw.Stop()
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
