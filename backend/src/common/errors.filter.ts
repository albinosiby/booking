import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from "@nestjs/common";
import { ZodError } from "zod";
import { randomUUID } from "node:crypto";
@Catch()
export class ErrorsFilter implements ExceptionFilter {
  private readonly logger = new Logger("API");
  catch(error: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse();
    const id = randomUUID();
    let status = 500,
      message = "Something went wrong. Please try again.",
      code = "INTERNAL_ERROR";
    if (error instanceof ZodError) {
      status = 422;
      message = error.issues
        .map((i) => `${i.path.join(".")}: ${i.message}`)
        .join("; ");
      code = "VALIDATION_ERROR";
    } else if (error instanceof HttpException) {
      status = error.getStatus();
      message = error.message;
      code =
        status === 409
          ? "CONFLICT"
          : status === 403
            ? "FORBIDDEN"
            : status === 401
              ? "UNAUTHENTICATED"
              : "REQUEST_ERROR";
    } else if (
      ["22021", "22P05", "22P02", "22001", "23514"].includes(
        (error as { code?: string })?.code ?? "",
      )
    ) {
      status = 422;
      message = "Some of the text or values entered are not valid.";
      code = "VALIDATION_ERROR";
    } else if ((error as { code?: string })?.code === "23505") {
      status = 409;
      message = "A record with these details already exists.";
      code = "CONFLICT";
    } else
      this.logger.error({
        requestId: id,
        error: error instanceof Error ? error.name : "UnknownError",
      });
    response.status(status).json({ code, message, request_id: id });
  }
}
