import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { StaffCashService } from "./staff-cash.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/staff-cash")
@UseGuards(AuthGuard)
export class StaffCashController {
  constructor(private readonly service: StaffCashService) {}
  @Header("Cache-Control", "private, no-store")
  @Get("me")
  me(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.me(r.actor, q);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("overview")
  overview(@Req() r: AuthRequest) {
    return this.service.overview(r.actor);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("history")
  history(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.history(r.actor, q);
  }
  @Header("Cache-Control", "private, no-store")
  @Post(":membershipId/settle")
  settle(
    @Req() r: AuthRequest,
    @Param("membershipId", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.settle(r.actor, id, b);
  }
}
