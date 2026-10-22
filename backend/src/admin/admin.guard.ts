import { CanActivate, ExecutionContext, Injectable } from "@nestjs/common";
import { panelActor } from "./panel-auth";

@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    const proof = request.headers["x-bookingos-admin"];
    request.actor = panelActor(
      typeof proof === "string" ? proof : undefined,
      request.method,
      request.originalUrl,
      request.body,
    );
    return true;
  }
}
