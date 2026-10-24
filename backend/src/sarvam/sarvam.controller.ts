import {
  Body,
  Controller,
  Get,
  Headers,
  Header,
  HttpCode,
  Post,
  Put,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { SarvamService } from "./sarvam.service";
import { VoiceService } from "./voice.service";
import { AgentCallService } from "../agent-calls/agent-calls.service";
import { voiceResult } from "./voice-result";
type AuthRequest = Request & { actor: Actor };
/** Public tool endpoints for Sarvam, authenticated by the X-API-Key tool key. */
@Controller("voice/v1")
export class VoiceController {
  constructor(
    private readonly sarvam: SarvamService,
    private readonly voice: VoiceService,
    private readonly calls: AgentCallService,
  ) {}
  @Header("Cache-Control", "no-store")
  @Post("call-events")
  @HttpCode(200)
  async event(
    @Headers("x-api-key") key: string | undefined,
    @Body() body: unknown,
  ) {
    const actor = await this.sarvam.authenticateToolKey(key ?? null, true);
    return this.calls.recordEvent(actor, body);
  }
  private async run(
    key: string | undefined,
    work: (actor: Actor) => Promise<unknown>,
  ) {
    const actor = await this.sarvam.authenticateToolKey(key ?? null);
    return voiceResult(() => work(actor));
  }
  @Header("Cache-Control", "no-store")
  @Post("catalog")
  @HttpCode(200)
  catalog(@Headers("x-api-key") k?: string) {
    return this.run(k, (a) => this.voice.catalog(a));
  }
  @Header("Cache-Control", "no-store")
  @Post("availability")
  @HttpCode(200)
  availability(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.availability(a, b));
  }
  @Header("Cache-Control", "no-store")
  @Post("bookings")
  @HttpCode(200)
  book(@Headers("x-api-key") k: string | undefined, @Body() b: unknown) {
    return this.run(k, (a) => this.voice.book(a, b));
  }
  @Header("Cache-Control", "no-store")
  @Post("my-bookings")
  @HttpCode(200)
  mine(@Headers("x-api-key") k: string | undefined, @Body() b: unknown) {
    return this.run(k, (a) => this.voice.mine(a, b));
  }
  @Header("Cache-Control", "no-store")
  @Post("reschedule")
  @HttpCode(200)
  reschedule(@Headers("x-api-key") k: string | undefined, @Body() b: unknown) {
    return this.run(k, (a) => this.voice.reschedule(a, b));
  }
  @Header("Cache-Control", "no-store")
  @Post("cancel")
  @HttpCode(200)
  cancel(@Headers("x-api-key") k: string | undefined, @Body() b: unknown) {
    return this.run(k, (a) => this.voice.cancel(a, b));
  }
}

/** OAuth state is one-time, expires after ten minutes and identifies the pending tenant. */
@Controller("v1/sarvam/oauth")
export class SarvamOAuthController {
  constructor(private readonly service: SarvamService) {}
  @Header("Cache-Control", "no-store")
  @Get("callback")
  async callback(@Query() q: unknown, @Res() res: Response) {
    await this.service.oauthCallback(q);
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Referrer-Policy", "no-referrer");
    res
      .type("html")
      .send(
        "<!doctype html><title>BookingOS</title><p>Authorization processed. Return to BookingOS to continue setup.</p>",
      );
  }
}
