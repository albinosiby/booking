import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Actor, AuthGuard } from "../common/auth.guard";
import { NotificationService } from "./notification.service";

@Controller("v1/notifications/devices")
@UseGuards(AuthGuard)
export class NotificationController {
  constructor(private readonly notifications: NotificationService) {}
  @Post() register(@Req() req: { actor: Actor }, @Body() input: unknown) {
    return this.notifications.register(req.actor, input);
  }
  @Post(":id/unregister") unregister(
    @Req() req: { actor: Actor },
    @Param("id") id: string,
    @Body() input: unknown,
  ) {
    return this.notifications.unregister(req.actor, id, input);
  }
}

@Controller("v1/notifications")
@UseGuards(AuthGuard)
export class NotificationInboxController {
  constructor(private readonly notifications: NotificationService) {}
  @Get("inbox") list(
    @Req() req: { actor: Actor },
    @Query("before") before?: string,
  ) {
    return this.notifications.list(req.actor, before);
  }
}

@Controller("v1/notifications/installations")
export class NotificationInstallationController {
  constructor(private readonly notifications: NotificationService) {}
  @Post("revoke") revoke(@Body() input: unknown) {
    return this.notifications.revokeInstallation(input);
  }
}
