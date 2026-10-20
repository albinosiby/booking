import {
  Body,
  Controller,
  Delete,
  Get,
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
import { z } from "zod";
import { Actor, AuthGuard } from "../common/auth.guard";
import { ExpensesService } from "./expenses.service";
import { renderExpenseReport } from "./expenses.report";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/expenses")
@UseGuards(AuthGuard)
export class ExpensesController {
  constructor(private readonly s: ExpensesService) {}
  @Get("catalog") catalog(@Req() r: AuthRequest) {
    return this.s.catalog(r.actor);
  }
  @Post("categories") category(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.s.category(r.actor, b);
  }
  @Patch("categories/:id") edit(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.s.category(r.actor, b, id);
  }
  @Get("overview") overview(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.s.overview(r.actor, q);
  }
  @Get() list(@Req() r: AuthRequest, @Query() q: unknown) {
    return this.s.list(r.actor, q);
  }
  @Post() create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.s.create(r.actor, b);
  }
  @Get("reports/:format") async report(
    @Req() r: AuthRequest,
    @Query() q: unknown,
    @Param("format") format: string,
    @Res() res: Response,
  ) {
    z.enum(["pdf", "xlsx"]).parse(format);
    const d = await this.s.report(r.actor, q),
      bytes = await renderExpenseReport(d, format);
    res.setHeader(
      "Content-Type",
      format === "pdf"
        ? "application/pdf"
        : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    );
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="expenses-${d.from}-${d.until}.${format}"`,
    );
    res.setHeader("Cache-Control", "no-store");
    res.send(bytes);
  }
  @Get(":id") detail(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.s.detail(r.actor, id);
  }
  @Post(":id/attachments") prepare(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.s.prepare(r.actor, id, b);
  }
  @Post(":id/attachments/:file/complete") complete(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("file", ParseUUIDPipe) file: string,
  ) {
    return this.s.complete(r.actor, id, file);
  }
  @Get(":id/attachments/:file") attachment(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("file", ParseUUIDPipe) file: string,
  ) {
    return this.s.attachment(r.actor, id, file);
  }
  @Delete(":id/attachments/:file") remove(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("file", ParseUUIDPipe) file: string,
  ) {
    return this.s.removePending(r.actor, id, file);
  }
}
