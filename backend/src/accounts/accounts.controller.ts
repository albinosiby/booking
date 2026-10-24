import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { AccountsService } from "./accounts.service";
import { renderReport } from "./accounts.report";
import { z } from "zod";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/accounts")
@UseGuards(AuthGuard)
export class AccountsController {
  constructor(private readonly service: AccountsService) {}
  @Get("catalog") catalog(@Req() r: AuthRequest) {
    return this.service.catalog(r.actor);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("website-payments")
  websitePayments(@Req() r: AuthRequest) {
    return this.service.websitePayments(r.actor);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("website-payments")
  saveWebsitePayments(@Req() r: AuthRequest, @Body() body: unknown) {
    return this.service.saveWebsitePayments(r.actor, body);
  }
  @Get("overview") overview(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.service.overview(r.actor, q);
  }
  @Get("transactions") transactions(
    @Req() r: AuthRequest,
    @Query() q: unknown,
  ) {
    return this.service.transactions(r.actor, q);
  }
  @Post("cash/opening") cashOpening(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.cashOpening(r.actor, b);
  }
  @Post("banks") create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.createAccount(r.actor, b);
  }
  @Patch("banks/:id") update(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.updateAccount(r.actor, id, b);
  }
  @Post("routes") route(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.route(r.actor, b);
  }
  @Post("entries") entry(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.createEntry(r.actor, b);
  }
  @Post("entries/:id/reverse") reverse(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.reverse(r.actor, id, b);
  }
  @Get("reports/:format") async report(
    @Req() r: AuthRequest,
    @Param("format") format: string,
    @Query() q: Record<string, unknown>,
    @Res() res: Response,
  ) {
    z.enum(["pdf", "xlsx"]).parse(format);
    const type = z
      .enum(["monthly", "yearly", "bookings", "cash_flow"])
      .parse(q.type);
    const { type: _, ...filter } = q;
    const data = await this.service.report(r.actor, filter),
      bytes = await renderReport(data, format, type);
    res.setHeader(
      "Content-Type",
      format === "pdf"
        ? "application/pdf"
        : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    );
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="booking-os-${type}-${data.from}-${data.until}.${format}"`,
    );
    res.setHeader("Cache-Control", "no-store");
    res.send(bytes);
  }
}
