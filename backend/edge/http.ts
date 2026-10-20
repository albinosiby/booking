/** Framework-free HTTP primitives for the shared domain services on Edge. */
export const Injectable = () => (target: unknown) => target;
export class HttpException extends Error {
  constructor(
    message: string,
    private readonly status: number,
  ) {
    super(message);
  }
  getStatus() {
    return this.status;
  }
}
export class BadRequestException extends HttpException {
  constructor(message = "Bad request") {
    super(message, 400);
  }
}
export class UnauthorizedException extends HttpException {
  constructor(message = "Sign in to continue.") {
    super(message, 401);
  }
}
export class ForbiddenException extends HttpException {
  constructor(message = "Forbidden") {
    super(message, 403);
  }
}
export class NotFoundException extends HttpException {
  constructor(message = "Not found") {
    super(message, 404);
  }
}
export class ConflictException extends HttpException {
  constructor(message = "Conflict") {
    super(message, 409);
  }
}
export class ServiceUnavailableException extends HttpException {
  constructor(message = "Temporarily unavailable") {
    super(message, 503);
  }
}
