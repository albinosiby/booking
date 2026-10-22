import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { SupportService } from "./support.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/support/tickets")
@UseGuards(AuthGuard)
export class SupportController {
  constructor(private readonly service: SupportService) {}
  @Get() list(@Req() r: AuthRequest) {
    return this.service.list(r.actor);
  }
  @Post() create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.create(r.actor, b);
  }
  @Get(":id") detail(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.detail(r.actor, id);
  }
  @Post(":id/messages") message(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.addMessage(r.actor, id, b);
  }
}
