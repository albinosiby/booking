import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpException,
  Post,
  Put,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { ZodError } from "zod";
import { Actor, AuthGuard } from "../common/auth.guard";
import { SarvamService } from "./sarvam.service";
import { VoiceService } from "./voice.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/sarvam")
@UseGuards(AuthGuard)
export class SarvamController {
  constructor(private readonly service: SarvamService) {}
  @Get("settings") settings(@Req() r: AuthRequest) {
    return this.service.settings(r.actor);
  }
  @Put("settings") save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(r.actor, b);
  }
  @Post("tool-key") toolKey(@Req() r: AuthRequest) {
    return this.service.rotateToolKey(r.actor);
  }
  @Post("test") test(@Req() r: AuthRequest) {
    return this.service.test(r.actor);
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

/** Public tool endpoints for Sarvam, authenticated by the X-API-Key tool key. */
@Controller("voice/v1")
export class VoiceController {
  constructor(
    private readonly sarvam: SarvamService,
    private readonly voice: VoiceService,
  ) {}
  private async run(
    key: string | undefined,
    work: (actor: Actor) => Promise<unknown>,
  ) {
    const actor = await this.sarvam.authenticateToolKey(key ?? null);
    return voiceResult(() => work(actor));
  }
  @Post("catalog") @HttpCode(200) catalog(@Headers("x-api-key") k?: string) {
    return this.run(k, (a) => this.voice.catalog(a));
  }
  @Post("availability") @HttpCode(200) availability(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.availability(a, b));
  }
  @Post("bookings") @HttpCode(200) book(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.book(a, b));
  }
  @Post("my-bookings") @HttpCode(200) mine(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.mine(a, b));
  }
  @Post("reschedule") @HttpCode(200) reschedule(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.reschedule(a, b));
  }
  @Post("cancel") @HttpCode(200) cancel(
    @Headers("x-api-key") k: string | undefined,
    @Body() b: unknown,
  ) {
    return this.run(k, (a) => this.voice.cancel(a, b));
  }
}

/**
 * Expected refusals (slot taken, unknown space, not the caller's booking) are
 * returned as 200 `{ok:false,message}` so the voice agent can say them.
 */
export async function voiceResult(work: () => Promise<unknown>) {
  try {
    return await work();
  } catch (error) {
    if (error instanceof ZodError)
      return {
        ok: false,
        message:
          "Some details are missing: " +
          error.issues.map((i) => i.path.join(".")).join(", ") +
          ".",
      };
    if (error instanceof HttpException && error.getStatus() < 500)
      return { ok: false, message: error.message };
    throw error;
  }
}
