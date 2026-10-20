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
import { CourtService } from "./court.service";
@Controller("v1/businesses")
@UseGuards(AuthGuard)
export class CourtController {
  constructor(private readonly service: CourtService) {}
  @Patch(":id/court-configuration") configure(
    @Req() request: Request & { actor: Actor },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.configure(request.actor, id, body);
  }
}
