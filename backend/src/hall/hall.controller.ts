import {
  Body,
  Controller,
  Param,
  ParseUUIDPipe,
  Patch,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { HallService } from "./hall.service";
@Controller("v1/businesses")
@UseGuards(AuthGuard)
export class HallController {
  constructor(private readonly service: HallService) {}
  @Patch(":id/hall-configuration") configure(
    @Req() request: Request & { actor: Actor },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.configure(request.actor, id, body);
  }
}
