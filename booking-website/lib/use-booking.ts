"use client";
import { useEffect, useMemo, useState, useRef } from "react";
import {
  BookingRequestError,
  PublicBookingRepository,
} from "./booking-repository";
import {
  bookingTimeCells,
  chooseTimeCell,
  preloadedEnds,
  rangeEnd,
} from "./booking-time-grid";
import type { TimeCell } from "./booking-time-grid";
import type {
  Confirmation,
  Quote,
  Selection,
  Slot,
  Website,
  Resource,
} from "./types";
type Command = {
  command_key: string;
  selection: Selection;
  quote_token: string;
  customer: { name: string; phone: string };
};
type Pending = { command: Command; quote: Quote; created: number };
export const dateAfter = (date: string, days: number) =>
  new Date(Date.parse(date + "T12:00:00Z") + days * 86400000)
    .toISOString()
    .slice(0, 10);
export { durationLabel, timeLabel, moneyLabel } from "./booking-format";
const message = (e: unknown) =>
  e instanceof Error ? e.message : "Something went wrong. Please retry.";

export function useBooking(
  slug: string,
  preview?: string,
  initialSite: Website | null = null,
) {
  const initialBusiness = initialSite?.businesses[0],
    initialResource = initialBusiness
      ? [...initialBusiness.resources].sort(
          (a, b) => b.section_ids.length - a.section_ids.length,
        )[0]
      : undefined;
  const repository = useMemo(
    () => new PublicBookingRepository(slug, preview),
    [slug, preview],
  );
  const [site, setSite] = useState<Website | null>(initialSite),
    [loading, setLoading] = useState(!initialSite),
    [error, setError] = useState("");
  const [businessId, setBusinessId] = useState(initialBusiness?.id ?? ""),
    [resourceId, setResourceId] = useState(initialResource?.id ?? ""),
    [optionId, setOptionId] = useState(initialResource?.options[0]?.id ?? ""),
    [date, setDate] = useState(initialBusiness?.today ?? "");
  const [people, setPeople] = useState(1),
    [start, setStart] = useState(""),
    [duration, setDuration] = useState(0),
    [slots, setSlots] = useState<Slot[]>([]),
    [slotLoading, setSlotLoading] = useState(false),
    [fallbackEnds, setFallbackEnds] = useState<{
      key: string;
      slots: Slot[];
    } | null>(null);
  const loadedSlotKey = useRef("");
  const [quote, setQuote] = useState<Quote | null>(null),
    [quoting, setQuoting] = useState(false),
    [mode, setMode] = useState<"slots" | "details" | "review" | "success">(
      "slots",
    );
  const [name, setName] = useState(""),
    [phone, setPhone] = useState(""),
    [confirming, setConfirming] = useState(false),
    [pending, setPending] = useState<Pending | null>(null),
    [uncertain, setUncertain] = useState(false),
    [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const [refresh, setRefresh] = useState(0),
    sending = useRef(false);
  const business = site?.businesses.find((b) => b.id === businessId),
    resource = business?.resources.find((r) => r.id === resourceId),
    option = resource?.options.find((o) => o.id === optionId);
  const selection: Selection | undefined =
    business && resource && option && date
      ? {
          business_id: business.id,
          resource_id: resource.id,
          option_id: option.id,
          date,
          time: start || option.fixed_time || "00:00",
          duration_minutes:
            duration || option.minimum_duration || option.default_duration,
          people: business.type === "pool" ? people : 1,
        }
      : undefined;
  const storageKey = `booking-pending:${slug}:${initialBusiness?.id ?? "all"}`;
  useEffect(() => {
    const abort = new AbortController();
    setLoading(!initialSite);
    setError("");
    (initialSite
      ? Promise.resolve(initialSite)
      : repository.catalog(abort.signal)
    )
      .then((value) => {
        setSite(value);
        const first = value.businesses[0];
        if (first) {
          const resources = [...first.resources].sort(
              (a, b) => b.section_ids.length - a.section_ids.length,
            ),
            r = resources[0];
          setBusinessId(first.id);
          setResourceId(r.id);
          setOptionId(r.options[0].id);
          setDate(first.today);
        }
        if (!preview) {
          try {
            const raw = sessionStorage.getItem(storageKey);
            if (raw) {
              const saved = JSON.parse(raw) as Pending;
              if (
                saved.created > Date.now() - 86400000 &&
                saved.command &&
                saved.quote
              ) {
                const s = saved.command.selection;
                setBusinessId(s.business_id);
                setResourceId(s.resource_id);
                setOptionId(s.option_id);
                setDate(s.date);
                setStart(s.time);
                setDuration(s.duration_minutes);
                setPeople(s.people);
                setName(saved.command.customer.name);
                setPhone(saved.command.customer.phone);
                setPending(saved);
                setQuote(saved.quote);
                setUncertain(true);
                setMode("review");
                setError(
                  "A previous confirmation needs verification. Retry it to check the same booking safely.",
                );
              } else sessionStorage.removeItem(storageKey);
            }
          } catch {
            /* Session storage may be disabled; in-memory retries remain safe. */
          }
        }
      })
      .catch((e) => {
        if (!abort.signal.aborted) setError(message(e));
      })
      .finally(() => {
        if (!abort.signal.aborted) setLoading(false);
      });
    return () => abort.abort();
  }, [repository, preview, storageKey, initialSite]);
  const reset = () => {
    setStart("");
    setDuration(0);
    setQuote(null);
    setSlots([]);
    setError("");
    setMode("slots");
  };
  function chooseBusiness(id: string) {
    if (pending) return;
    const b = site?.businesses.find((b) => b.id === id);
    if (!b) return;
    const r = [...b.resources].sort(
      (a, b) => b.section_ids.length - a.section_ids.length,
    )[0];
    reset();
    setBusinessId(id);
    setResourceId(r.id);
    setOptionId(r.options[0].id);
    setDate(b.today);
    setPeople(1);
  }
  function chooseResource(r: Resource) {
    if (pending) return;
    reset();
    setResourceId(r.id);
    setOptionId(
      (r.options.find((o) => o.sport === option?.sport) ?? r.options[0]).id,
    );
    setPeople(1);
  }
  function chooseOption(id: string) {
    if (pending) return;
    reset();
    setOptionId(id);
  }
  function chooseDate(value: string) {
    if (pending || !business) return;
    const first = business.today,
      last = dateAfter(first, site?.advance_days ?? 30);
    if (value < first || value > last) return;
    reset();
    setDate(value);
  }
  function changePeople(value: number) {
    if (
      pending ||
      !resource ||
      !Number.isInteger(value) ||
      value < 1 ||
      value > resource.capacity
    )
      return;
    reset();
    setPeople(value);
  }
  const availabilityKey = JSON.stringify(
    selection
      ? {
          ...selection,
          time: option?.fixed_time ?? "00:00",
          duration_minutes:
            option?.minimum_duration ?? option?.default_duration,
        }
      : null,
  );
  useEffect(() => {
    if (!selection || pending || mode !== "slots") return;
    const abort = new AbortController();
    setSlotLoading(true);
    if (loadedSlotKey.current !== availabilityKey) setSlots([]);
    setError("");
    repository
      .availability(
        JSON.parse(availabilityKey) as Selection,
        false,
        abort.signal,
      )
      .then((v) => {
        if (!abort.signal.aborted) {
          loadedSlotKey.current = availabilityKey;
          setSlots(v.slots);
        }
      })
      .catch((e) => {
        if (!abort.signal.aborted) setError(message(e));
      })
      .finally(() => {
        if (!abort.signal.aborted) setSlotLoading(false);
      });
    return () => abort.abort();
    // The canonical key includes all availability inputs; duration changes only reprice.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repository, availabilityKey, refresh, pending, mode]);
  const startSlot = slots.find(
    (slot) => slot.time === start && (!slot.date || slot.date === date),
  );
  const cachedEnds = useMemo(() => preloadedEnds(startSlot), [startSlot]);
  const endKey = JSON.stringify([availabilityKey, start, refresh]);
  useEffect(() => {
    if (
      !selection ||
      !start ||
      !option?.minimum_duration ||
      cachedEnds !== undefined ||
      slotLoading ||
      pending ||
      mode !== "slots"
    )
      return;
    const abort = new AbortController();
    setFallbackEnds(null);
    repository
      .availability(
        { ...selection, duration_minutes: option.minimum_duration },
        true,
        abort.signal,
      )
      .then((value) => {
        if (!abort.signal.aborted)
          setFallbackEnds({ key: endKey, slots: value.slots });
      })
      .catch((error) => {
        if (!abort.signal.aborted) {
          setFallbackEnds({ key: endKey, slots: [] });
          setError(message(error));
        }
      });
    return () => abort.abort();
    // End validation never replaces the original start grid; late responses are ignored.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repository, endKey, cachedEnds, slotLoading, pending, mode]);
  const endSlots =
    !start || !option?.minimum_duration
      ? []
      : (cachedEnds ??
        (fallbackEnds?.key === endKey ? fallbackEnds.slots : []));
  const endLoading =
    !!start &&
    !!option?.minimum_duration &&
    cachedEnds === undefined &&
    fallbackEnds?.key !== endKey;
  const timeCells = bookingTimeCells({
    date,
    start,
    duration,
    slots,
    endSlots,
    minimum: option?.minimum_duration ?? null,
    loading: slotLoading || endLoading,
    locked: !!pending,
    pool: business?.type === "pool",
  });
  const finish = rangeEnd(date, start, duration, endSlots);
  // The selection falls back to the minimum before a finish is chosen. Track
  // duration/start as dependencies too, including a minimum-length or midnight choice.
  const quoteKey = JSON.stringify(selection);
  useEffect(() => {
    if (mode === "success") {
      setError("");
      setQuoting(false);
      return;
    }
    if (pending || mode !== "slots") return;
    if (!selection || !start || !duration) {
      setQuote(null);
      return;
    }
    const abort = new AbortController();
    setQuote(null);
    setQuoting(true);
    setError("");
    repository
      .quote(selection, abort.signal)
      .then((value) => {
        if (!abort.signal.aborted) setQuote(value);
      })
      .catch((e) => {
        if (!abort.signal.aborted) setError(message(e));
      })
      .finally(() => {
        if (!abort.signal.aborted) setQuoting(false);
      });
    return () => abort.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repository, quoteKey, refresh, pending, mode, duration, start]);
  function chooseCell(cell: TimeCell) {
    if (!cell.enabled || pending || !option) return;
    const next = chooseTimeCell(
      { start, duration },
      cell,
      option.minimum_duration,
      option.default_duration,
    );
    setError("");
    setQuote(null);
    setQuoting(false);
    setStart(next.start);
    setDuration(next.duration);
  }
  async function confirm() {
    if (
      sending.current ||
      !site ||
      site.is_preview ||
      (!pending && (site.status !== "published" || !quote || !selection))
    )
      return;
    const saved: Pending = pending ?? {
      command: {
        command_key: crypto.randomUUID(),
        selection: selection!,
        quote_token: quote!.quote_token,
        customer: { name: name.trim(), phone: phone.trim() },
      },
      quote: quote!,
      created: Date.now(),
    };
    sending.current = true;
    setPending(saved);
    setConfirming(true);
    setError("");
    try {
      sessionStorage.setItem(storageKey, JSON.stringify(saved));
    } catch {}
    try {
      const result = await repository.book(saved.command);
      setConfirmation(result);
      setPending(null);
      setUncertain(false);
      setMode("success");
      try {
        sessionStorage.removeItem(storageKey);
      } catch {}
    } catch (e) {
      setError(message(e));
      if (
        !(e instanceof BookingRequestError) ||
        e.status === 0 ||
        e.status >= 500
      ) {
        setUncertain(true);
      } else {
        setPending(null);
        setUncertain(false);
        try {
          sessionStorage.removeItem(storageKey);
        } catch {}
        if (e.status === 409) {
          setQuote(null);
          setMode("slots");
          setStart("");
          setDuration(0);
          setRefresh((n) => n + 1);
          setError(
            "This slot or tariff changed. Select an available time and review again.",
          );
        }
      }
    } finally {
      sending.current = false;
      setConfirming(false);
    }
  }
  return {
    site,
    loading,
    error,
    business,
    resource,
    option,
    date,
    people,
    start,
    duration,
    slots,
    slotLoading,
    endLoading,
    timeCells,
    finish,
    quote,
    quoting,
    mode,
    name,
    phone,
    confirming,
    pending,
    uncertain,
    confirmation,
    repository,
    chooseBusiness,
    chooseResource,
    chooseOption,
    chooseDate,
    changePeople,
    chooseCell,
    confirm,
    setName,
    setPhone,
    changeStart: () => {
      if (!pending) {
        setStart("");
        setDuration(0);
        setQuote(null);
        setQuoting(false);
        setError("");
      }
    },
    continue: () => {
      if (quote && !pending) setMode("details");
    },
    review: () => {
      if (pending) return;
      const count = phone.replace(/\D/g, "").length;
      if (
        name.trim().length < 2 ||
        !/^\+?[\d ()-]{7,25}$/.test(phone.trim()) ||
        count < 7 ||
        count > 15
      ) {
        setError(
          "Enter your full name and a valid phone number with 7–15 digits.",
        );
        return;
      }
      setError("");
      setMode("review");
    },
    back: () => {
      if (!pending) setMode(mode === "review" ? "details" : "slots");
    },
    retry: () => setRefresh((n) => n + 1),
  };
}
