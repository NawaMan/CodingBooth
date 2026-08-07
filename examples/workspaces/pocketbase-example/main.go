// Tripboard — a small trip calendar backed by PocketBase.
//
// PocketBase is used here as a *framework*, not as a downloaded binary: it is
// an ordinary Go dependency this program embeds. So the database, the REST API
// and the admin UI all come out of the same `go build` as the custom route in
// trip.go, and the whole thing ships as one static binary.
//
// Run with:
//
//	go run . serve --http=0.0.0.0:8090
//
// Binding 0.0.0.0 matters inside a booth: the container publishes port 8090 to
// the host, and a server listening on 127.0.0.1 would ignore that mapping.
package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/pocketbase/pocketbase/tools/osutils"

	// Registers the schema and the seed trip via their init() functions.
	_ "tripboard/internal/migrations"
)

func main() {
	app := pocketbase.New()

	var automigrate bool
	app.RootCmd.PersistentFlags().BoolVar(&automigrate, "automigrate", true,
		"enable/disable auto migrations")

	var publicDir string
	app.RootCmd.PersistentFlags().StringVar(&publicDir, "publicDir", defaultPublicDir(),
		"the directory to serve static files")

	app.RootCmd.ParseFlags(os.Args[1:])

	// The schema is Go code under internal/migrations, so a fresh clone builds
	// its own database on first run — there is nothing to import by hand, and
	// no pb_data in the repo.
	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		TemplateLang: migratecmd.TemplateLangGo,
		Automigrate:  automigrate,
	})

	// The one route this app adds to what PocketBase already serves. See
	// trip.go for why the day-splitting belongs on the server.
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/trip", tripHandler)
		return e.Next()
	})

	// Serve pb_public last: it registers a catch-all, so a lower priority here
	// would let it shadow /api/trip and the built-in routes.
	app.OnServe().Bind(&hook.Handler[*core.ServeEvent]{
		Func: func(e *core.ServeEvent) error {
			if !e.Router.HasRoute(http.MethodGet, "/{path...}") {
				e.Router.GET("/{path...}", apis.Static(os.DirFS(publicDir), false))
			}
			return e.Next()
		},
		Priority: 999,
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}

// defaultPublicDir keeps `go run .` and a built binary looking in the same
// place: the working directory during development, and next to the executable
// once it is built and moved somewhere.
func defaultPublicDir() string {
	if osutils.IsProbablyGoRun() {
		return "./pb_public"
	}
	return filepath.Join(os.Args[0], "../pb_public")
}
