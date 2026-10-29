import { HttpException } from "@nestjs/common";

/** An application-owned error code; untrusted provider bodies never become one. */
export class DomainHttpError extends HttpException {
  constructor(
    readonly code: string,
    status: number,
    message: string,
  ) {
    super({ code, message }, status);
  }
}
