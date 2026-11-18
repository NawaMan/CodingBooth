package migrations

import (
	"time"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

func init() {
	m.Register(up_1700000002, down_1700000002)
}

// seedEvent is one line of the demo trip, in the order it happens.
//
// The trip is invented — five days in Portugal that nobody took, with made-up
// booking references. It exists so the calendar has something to draw the
// moment the server starts: an empty grid teaches nothing about what the
// layout does with an overnight hotel or two things happening at once.
type seedEvent struct {
	title        string
	kind         string
	certainty    string
	start        time.Time
	end          time.Time // zero for a moment with no duration
	location     string
	locationEnd  string
	confirmation string
	notes        string
}

// Wall-clock trip time. UTC here is the storage convention, not a timezone
// claim — see the starts_at comment in the collection migration.
func at(day, hour, min int) time.Time {
	return time.Date(2026, 9, day, hour, min, 0, 0, time.UTC)
}

var seedTrip = []seedEvent{
	{
		title: "Flight to Lisbon", kind: "flight", certainty: "mandatory",
		start: at(14, 9, 40), end: at(14, 12, 5),
		location: "Berlin BER", locationEnd: "Lisbon LIS",
		confirmation: "DEMO-4821",
		notes:        "Two checked bags. Aisle seats on the second row from the back.",
	},
	{
		// Three days wide: the calendar cuts it at midnight twice and each day
		// keeps the part it owns.
		title: "Hotel Alfama Rooftop", kind: "hotel", certainty: "mandatory",
		start: at(14, 15, 0), end: at(16, 11, 0),
		location:     "Lisbon",
		confirmation: "DEMO-77Q4",
		notes:        "Late check-in is fine; the desk is staffed all night.",
	},
	{
		// No end time: a moment, not a block.
		title: "Dinner by the river", kind: "activity", certainty: "tentative",
		start:    at(14, 20, 0),
		location: "Cais do Sodré",
	},
	{
		title: "Old town walking tour", kind: "activity", certainty: "mandatory",
		start: at(15, 10, 0), end: at(15, 12, 30),
		location: "Praça do Comércio",
		notes:    "Meet under the arch fifteen minutes early.",
	},
	{
		// Overlaps nothing, but it is the tentative half of the day.
		title: "Tram 28, end to end", kind: "activity", certainty: "tentative",
		start: at(15, 15, 0), end: at(15, 16, 30),
		location: "Martim Moniz",
	},
	{
		title: "Train to Porto", kind: "train", certainty: "mandatory",
		start: at(16, 13, 15), end: at(16, 16, 5),
		location: "Lisboa Oriente", locationEnd: "Porto Campanhã",
		confirmation: "DEMO-3155",
	},
	{
		title: "Hotel Ribeira Nights", kind: "hotel", certainty: "mandatory",
		start: at(16, 17, 0), end: at(18, 10, 0),
		location:     "Porto",
		confirmation: "DEMO-90KD",
	},
	{
		title: "Douro valley, by bus", kind: "bus", certainty: "tentative",
		start: at(17, 8, 30), end: at(17, 18, 30),
		location: "Porto", locationEnd: "Douro Valley",
		notes: "Not booked yet — decide the evening before, weather permitting.",
	},
	{
		title: "Flight home", kind: "flight", certainty: "mandatory",
		start: at(18, 12, 40), end: at(18, 17, 20),
		location: "Porto OPO", locationEnd: "Berlin BER",
		confirmation: "DEMO-4822",
	},
}

func up_1700000002(app core.App) error {
	col, err := app.FindCollectionByNameOrId(ColTripEvents)
	if err != nil {
		return err
	}

	for _, ev := range seedTrip {
		rec := core.NewRecord(col)
		rec.Set("title", ev.title)
		rec.Set("kind", ev.kind)
		rec.Set("certainty", ev.certainty)
		rec.Set("starts_at", ev.start)
		if !ev.end.IsZero() {
			rec.Set("ends_at", ev.end)
		}
		rec.Set("location", ev.location)
		rec.Set("location_end", ev.locationEnd)
		rec.Set("confirmation", ev.confirmation)
		rec.Set("notes", ev.notes)

		if err := app.Save(rec); err != nil {
			return err
		}
	}

	return nil
}

// Reverting removes the demo trip and leaves anything you added alone, which
// is why it matches on title and start time rather than emptying the table.
func down_1700000002(app core.App) error {
	for _, ev := range seedTrip {
		records, err := app.FindRecordsByFilter(
			ColTripEvents,
			`title = {:title} && starts_at = {:start}`,
			"-created",
			10,
			0,
			map[string]any{
				"title": ev.title,
				"start": ev.start.UTC().Format("2006-01-02 15:04:05.000Z"),
			},
		)
		if err != nil {
			return err
		}
		for _, rec := range records {
			if err := app.Delete(rec); err != nil {
				return err
			}
		}
	}

	return nil
}
