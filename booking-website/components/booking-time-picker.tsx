"use client";
import { Icon } from "./icons";
import type { TimeCell } from "../lib/booking-time-grid";
import { minutesLabel } from "../lib/booking-time-grid";

import { timeLabel } from "../lib/booking-format";
export function BookingTimePicker({
  date,
  start,
  duration,
  finish,
  minimum,
  cells,
  loading,
  locked,
  onSelect,
  onRefresh,
}: {
  date: string;
  start: string;
  duration: number;
  finish: string | null;
  minimum: number | null;
  cells: TimeCell[];
  loading: boolean;
  locked: boolean;
  onSelect: (cell: TimeCell) => void;
  onRefresh: () => void;
}) {
  return (
    <div className="time-card">
      <div className="time-card-heading">
        <h3>{minimum ? "Choose start & end" : "Choose your time"}</h3>
        <p>
          {minimum
            ? `Minimum booking: ${minutesLabel(minimum)}. “Available · cannot start” means the time is free, but a minimum-length booking cannot start there. Choose a start, then an end. Tap a selected boundary again to clear it.`
            : "Choose an available session below."}
        </p>
        {!!minimum && (
          <dl
            className="time-selection"
            aria-live="polite"
            aria-label="Selected booking time"
          >
            <div>
              <dt>Start</dt>
              <dd>{start ? timeLabel(start) : "—"}</dd>
            </div>
            <div>
              <dt>End</dt>
              <dd>
                {finish ? (
                  <>
                    {timeLabel(finish.slice(11, 16))}
                  </>
                ) : (
                  "—"
                )}
              </dd>
            </div>
            <div>
              <dt>Duration</dt>
              <dd>{duration ? minutesLabel(duration) : "—"}</dd>
            </div>
          </dl>
        )}
        <div className="time-selection-status" role="status">
          {loading
            ? "Checking availability…"
            : minimum
              ? !start
                ? "Choose a start slot."
                : !duration
                  ? "Now choose an end slot in the same grid."
                  : "Range selected. Choose another available slot to start again."
              : "Choose a session."}
        </div>
      </div>
      {cells.length === 0 ? (
        loading ? (
          <div className="slots-loading">
            <div className="loader" />
            Checking availability…
          </div>
        ) : (
          <div className="empty-state">
            <Icon name="clock" size={28} />
            <h3>No times available</h3>
            <p>Try another date or space.</p>
            <button
              className="text-button"
              disabled={locked}
              onClick={onRefresh}
            >
              Refresh availability
            </button>
          </div>
        )
      ) : (
        <div
          className="time-grid"
          aria-label={minimum ? "Start and end slots" : "Available sessions"}
          aria-busy={loading}
        >
          {cells.map((cell) => {
            const boundary = cell.start || cell.end;
            const selected =
              boundary ||
              cell.inRange ||
              (!minimum && cell.slot.time === start && cell.date === date);
            const day = cell.date !== date ? " +1 day" : "";
            return (
              <button
                key={cell.key}
                type="button"
                className={`time-tile ${selected ? "selected" : ""} ${boundary ? "range-boundary" : ""} ${cell.inRange ? "in-range" : ""} ${!cell.enabled ? "unavailable" : ""}`}
                disabled={!cell.enabled}
                aria-pressed={selected}
                aria-label={`${timeLabel(cell.slot.time)}${day}, ${cell.label}`}
                data-time={cell.key}
                onClick={() => onSelect(cell)}
              >
                <strong>
                  {timeLabel(cell.slot.time)}
                </strong>
                <span>{cell.label}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
