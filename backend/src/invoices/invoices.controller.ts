import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { InvoicesService } from "./invoices.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/invoices")
@UseGuards(AuthGuard)
export class InvoicesController {
  constructor(private readonly service: InvoicesService) {}
  @Header("Cache-Control", "private, no-store")
  @Get("settings")
  settings(@Req() r: AuthRequest) {
    return this.service.settings(r.actor);
  }
  @Header("Cache-Control", "private, no-store")
  @Put("settings")
  saveSettings(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.saveSettings(r.actor, b);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("bookings/:bookingId")
  list(
    @Req() r: AuthRequest,
    @Param("bookingId", ParseUUIDPipe) bookingId: string,
  ) {
    return this.service.list(r.actor, bookingId);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("bookings/:bookingId")
  generate(
    @Req() r: AuthRequest,
    @Param("bookingId", ParseUUIDPipe) bookingId: string,
    @Body() b: unknown,
  ) {
    return this.service.generate(r.actor, bookingId, b);
  }
  @Get(":id/pdf")
  async pdf(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Res() res: Response,
  ) {
    const { bytes, filename } = await this.service.pdf(r.actor, id);
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
    res.setHeader("Cache-Control", "private, no-store");
    res.send(bytes);
  }
}
