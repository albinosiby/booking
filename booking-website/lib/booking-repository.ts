import type { Confirmation, Quote, Selection, Slot, Website } from "./types";
export class BookingRequestError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}
export class PublicBookingRepository {
  constructor(
    readonly slug: string,
    readonly preview?: string,
  ) {}
  url(operation = "") {
    return `/api/sites/${encodeURIComponent(this.slug)}${operation ? "/" + operation : ""}${this.preview ? "?preview=" + encodeURIComponent(this.preview) : ""}`;
  }
  async request<T>(
    operation: string,
    body?: unknown,
    signal?: AbortSignal,
  ): Promise<T> {
    let response: Response;
    try {
      response = await fetch(this.url(operation), {
        method: body === undefined ? "GET" : "POST",
        headers:
          body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
        cache: "no-store",
        signal,
      });
    } catch (e) {
      if (signal?.aborted) throw e;
      throw new BookingRequestError(
        "Connection interrupted. Please try again.",
        0,
      );
    }
    const result = await response.json().catch(() => null);
    if (!response.ok)
      throw new BookingRequestError(
        result?.message ??
          "The booking service could not complete this request.",
        response.status,
      );
    return result;
  }
  catalog(signal?: AbortSignal) {
    return this.request<Website>("", undefined, signal);
  }
  availability(selection: Selection, endTimes = false, signal?: AbortSignal) {
    return this.request<{ slots: Slot[] }>(
      "availability",
      { selection, end_times: endTimes },
      signal,
    );
  }
  quote(selection: Selection, signal?: AbortSignal) {
    return this.request<Quote>("quote", { selection }, signal);
  }
  book(command: {
    command_key: string;
    selection: Selection;
    quote_token: string;
    customer: { name: string; phone: string };
  }) {
    return this.request<Confirmation>("bookings", command);
  }
}
