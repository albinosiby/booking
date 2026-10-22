import {
  Body,
  Controller,
  Get,
  Post,
  Put,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { AgentCallService } from "./agent-calls.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/agent-calls")
@UseGuards(AuthGuard)
export class AgentCallController {
  constructor(private readonly service: AgentCallService) {}
  @Get() status(@Req() r: AuthRequest) {
    return this.service.status(r.actor);
  }
  @Post("request") request(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.request(r.actor, b);
  }
  @Put("enabled") enabled(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.setEnabled(r.actor, b);
  }
  @Get("calls") calls(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.calls(r.actor, q);
  }
  @Get("transcript") transcript(
    @Req() r: AuthRequest,
    @Query("interaction_id") id: string,
  ) {
    return this.service.transcript(r.actor, id);
  }
  @Get("recording") async recording(
    @Req() r: AuthRequest,
    @Query("interaction_id") id: string,
    @Res() res: Response,
  ) {
    const audio = await this.service.recording(r.actor, id);
    res
      .type(audio.content_type)
      .setHeader("Content-Disposition", 'attachment; filename="call.wav"')
      .send(Buffer.from(audio.data));
  }
}
