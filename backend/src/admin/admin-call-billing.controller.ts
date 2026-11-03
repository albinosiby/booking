import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import type { Actor } from "../common/auth.guard";
import { AdminGuard } from "./admin.guard";
import { AdminCallBillingService } from "./admin-call-billing.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/admin")
@UseGuards(AdminGuard)
export class AdminCallBillingController {
  constructor(private readonly service: AdminCallBillingService) {}
  @Get("call-billing") defaults(@Req() r: AuthRequest) {
    return this.service.defaults(r.actor);
  }
  @Put("call-billing") saveDefaults(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.saveDefaults(r.actor, b);
  }
  @Get("organizations/:id/call-wallet") wallet(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Query() q: Record<string, string>,
  ) {
    return this.service.wallet(r.actor, id, q);
  }
  @Put("organizations/:id/call-wallet/pricing") pricing(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.saveOverrides(r.actor, id, b);
  }
  @Post("organizations/:id/call-wallet/adjustments") adjust(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.adjust(r.actor, id, b);
  }
}
