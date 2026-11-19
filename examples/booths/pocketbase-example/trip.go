package main

import (
	"net/http"
	"time"

	"github.com/pocketbase/pocketbase/core"

	"tripboard/internal/migrations"
)

// A demo trip is a handful of events; the ceiling only stops a runaway query
// from trying to serialise an unbounded result set.
const maxTripEvents = 500

// tripDay is one day of the trip and everything happening on it.
//
// An event can appear on more than one day — a hotel night starts on the 14th
// and ends on the 15th, and both days should show it. Cutting it at midnight
// here rather than in the browser means the page can render a day by walking a
// list, and it is the reason this route exists at all: PocketBase's built-in
// /api/collections/trip_events/records is right there and returns the same
// records, just not already arranged the way a calendar reads them.
type tripDay struct {
	Date   string         `json:"date"` // YYYY-MM-DD
	Events []*core.Record `json:"events"`
}

type tripResponse struct {
	Start string    `json:"start"`
	End   string    `json:"end"`
	Days  []tripDay `json:"days"`
}

func tripHandler(e *core.RequestEvent) error {
	records, err := e.App.FindRecordsByFilter(
		migrations.ColTripEvents, "id != ''", "starts_at", maxTripEvents, 0)
	if err != nil {
		return e.InternalServerError("could not load the trip", err)
	}

	resp := tripResponse{Days: []tripDay{}}
	if len(records) == 0 {
		return e.JSON(http.StatusOK, resp)
	}

	// Records come back sorted by starts_at, so the first one opens the trip.
	// The last day has to be searched for: an event that starts earlier can
	// still end later than every event after it.
	first := startOf(records[0])
	firstDay := dayOf(first)
	lastDay := firstDay
	for _, rec := range records {
		end := endOf(rec)
		// An event ending exactly at midnight belongs to the day before it,
		// not to the empty one it touches for an instant.
		if d := dayOf(end.Add(-time.Nanosecond)); d.After(lastDay) {
			lastDay = d
		}
	}

	for day := firstDay; !day.After(lastDay); day = day.AddDate(0, 0, 1) {
		next := day.AddDate(0, 0, 1)
		today := tripDay{Date: day.Format("2006-01-02"), Events: []*core.Record{}}
		for _, rec := range records {
			if overlaps(rec, day, next) {
				today.Events = append(today.Events, rec)
			}
		}
		resp.Days = append(resp.Days, today)
	}

	resp.Start = resp.Days[0].Date
	resp.End = resp.Days[len(resp.Days)-1].Date

	return e.JSON(http.StatusOK, resp)
}

// overlaps reports whether an event is on screen for [day, next).
func overlaps(rec *core.Record, day, next time.Time) bool {
	start := startOf(rec)
	end := endOf(rec)

	// A moment in time — a meeting point, a museum entry — has no duration to
	// straddle midnight with, so it is simply on the day it happens.
	if end.Equal(start) {
		return !start.Before(day) && start.Before(next)
	}

	return start.Before(next) && end.After(day)
}

func startOf(rec *core.Record) time.Time {
	return rec.GetDateTime("starts_at").Time()
}

// endOf falls back to the start: an event without ends_at is a moment, not an
// event running to the end of time.
func endOf(rec *core.Record) time.Time {
	end := rec.GetDateTime("ends_at").Time()
	if end.IsZero() {
		return startOf(rec)
	}
	return end
}

// dayOf truncates to midnight. Times are stored as wall-clock components in
// UTC (see the migration), so this is the trip's own midnight rather than
// whatever midnight the server's timezone happens to be at.
func dayOf(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
