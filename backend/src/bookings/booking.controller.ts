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
import { BookingService } from "./booking.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/bookings")
@UseGuards(AuthGuard)
export class BookingController {
  constructor(private readonly service: BookingService) {}
  @Get("catalog") catalog(@Req() r: AuthRequest) {
    return this.service.catalog(r.actor);
  }
  @Get("date-counts") dateCounts(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.dateCounts(r.actor, q);
  }
  @Get("customers") customers(@Req() r: AuthRequest, @Query("q") q = "") {
    return this.service.customers(r.actor, q);
  }
  @Get("customer-directory") customerDirectory(
    @Req() r: AuthRequest,
    @Query() q: unknown,
  ) {
    return this.service.customerDirectory(r.actor, q);
  }
  @Get("customer-directory/:id") customerHistory(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() q: unknown,
  ) {
    return this.service.customerHistory(r.actor, id, q);
  }
  @Get("dashboard") dashboard(
    @Req() r: AuthRequest,
    @Query("business_id") id?: string,
  ) {
    return this.service.dashboard(r.actor, id);
  }
  @Get("outstanding") outstanding(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.outstanding(r.actor, q);
  }
  @Get("collections") collections(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.paymentList(r.actor, q);
  }
  @Get("commands/:key") command(
    @Req() r: AuthRequest,
    @Param("key", ParseUUIDPipe) key: string,
  ) {
    return this.service.commandResult(r.actor, key);
  }
  @Post("quote") quote(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.service.quote(r.actor, body);
  }
  @Post("availability") availability(
    @Req() r: AuthRequest,
    @Body() body: unknown,
  ) {
    return this.service.availability(r.actor, body);
  }
  @Post() create(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.service.create(r.actor, body);
  }
  @Get() list(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.list(r.actor, q);
  }
  @Get(":id") detail(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.detail(r.actor, id);
  }
  @Post(":id/reschedule") reschedule(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.reschedule(r.actor, id, body);
  }
  @Post(":id/payments") payments(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.payments(r.actor, id, body);
  }
  @Post(":id/status") status(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.status(r.actor, id, body);
  }
  @Post(":id/customer") customer(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.editCustomer(r.actor, id, body);
  }
}
