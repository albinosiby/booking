import {
  Body,
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { CallWalletService } from "./call-wallet.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/call-wallet")
@UseGuards(AuthGuard)
export class CallWalletController {
  constructor(private readonly service: CallWalletService) {}
  @Get() status(@Req() r: AuthRequest) {
    return this.service.status(r.actor);
  }
  @Get("transactions") transactions(
    @Req() r: AuthRequest,
    @Query() q: unknown,
  ) {
    return this.service.transactions(r.actor, q);
  }
  @Post("orders") create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.createOrder(r.actor, b);
  }
  @Post("orders/:id/verify") @HttpCode(200) verify(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.verify(r.actor, id);
  }
}
/** Public endpoint for the payment backend, authenticated by an HMAC signature. */
@Controller("v1/call-wallet/payment-events")
export class CallWalletEventsController {
  constructor(private readonly service: CallWalletService) {}
  @Header("Cache-Control", "no-store")
  @Post()
  @HttpCode(200)
  event(
    @Headers("x-booking-pg-timestamp") timestamp: string | undefined,
    @Headers("x-booking-pg-signature") signature: string | undefined,
    @Body() body: unknown,
  ) {
    return this.service.paymentEvent(
      { timestamp: timestamp ?? null, signature: signature ?? null },
      body,
    );
  }
}
