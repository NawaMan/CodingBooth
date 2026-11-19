// Package migrations defines the Tripboard schema as versioned Go code.
//
// Writing the schema here rather than clicking it together in the admin UI is
// what makes the example reproducible: `go run . serve` on a fresh clone
// builds the same database every time, and the repo carries no pb_data.
package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// ColTripEvents is the one collection this example has.
const ColTripEvents = "trip_events"

func init() {
	m.Register(up_1700000001, down_1700000001)
}

func up_1700000001(app core.App) error {
	events := core.NewBaseCollection(ColTripEvents)

	// Public read, so the calendar page needs no login. Writes are left
	// superuser-only (a nil rule): edit through the admin UI at /_/, or with a
	// superuser token. Loosen these two lines and the same records become
	// world-writable — which is the whole of PocketBase's access control, and
	// worth seeing in one place.
	events.ListRule = types.Pointer("")
	events.ViewRule = types.Pointer("")

	events.Fields.Add(
		&core.TextField{Name: "title", Required: true, Max: 300, Presentable: true},

		&core.SelectField{
			Name:      "kind",
			Required:  true,
			MaxSelect: 1,
			Values:    []string{"flight", "train", "bus", "hotel", "activity", "other"},
		},

		// Half a trip is booked and half is an intention; the calendar draws
		// the difference (a dashed edge) instead of hiding it.
		&core.SelectField{
			Name:      "certainty",
			Required:  true,
			MaxSelect: 1,
			Values:    []string{"mandatory", "tentative"},
		},

		// Trip wall-clock time, stored as UTC components. A flight that leaves
		// at 09:40 should be drawn at 09:40 whatever timezone the browser is
		// in, so the times carry no offset to be re-interpreted.
		&core.DateField{Name: "starts_at", Required: true},
		&core.DateField{Name: "ends_at"},

		&core.TextField{Name: "location", Max: 300},
		&core.TextField{Name: "location_end", Max: 300},
		&core.TextField{Name: "confirmation", Max: 200},
		&core.EditorField{Name: "notes"},

		&core.AutodateField{Name: "created", OnCreate: true},
		&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
	)

	events.AddIndex("idx_trip_events_starts_at", false, "starts_at", "")

	return app.Save(events)
}

func down_1700000001(app core.App) error {
	col, err := app.FindCollectionByNameOrId(ColTripEvents)
	if err != nil {
		return err
	}
	return app.Delete(col)
}
