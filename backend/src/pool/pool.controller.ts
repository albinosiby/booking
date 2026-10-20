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
import { PoolService } from "./pool.service";
@Controller("v1/businesses")
@UseGuards(AuthGuard)
export class PoolController {
  constructor(private readonly service: PoolService) {}
  @Patch(":id/pool-configuration") configure(
    @Req() request: Request & { actor: Actor },
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.configure(request.actor, id, body);
  }
}
