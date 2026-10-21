import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { SlotBlocksService } from "./slot-blocks.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/booking-blocks")
@UseGuards(AuthGuard)
export class SlotBlocksController {
  constructor(private readonly service: SlotBlocksService) {}
  @Get() list(@Req() req: AuthRequest, @Query() query: unknown) {
    return this.service.list(req.actor, query);
  }
  @Get("slots") slots(@Req() req: AuthRequest, @Query() query: unknown) {
    return this.service.slots(req.actor, query);
  }
  @Post() create(@Req() req: AuthRequest, @Body() body: unknown) {
    return this.service.create(req.actor, body);
  }
  @Post(":id/unblock") unblock(
    @Req() req: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.unblock(req.actor, id, body);
  }
}
