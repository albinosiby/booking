import {
  Body,
  Controller,
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
import { IncomeService } from "./income.service";
import { renderIncomeReport } from "./income.report";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/income")
@UseGuards(AuthGuard)
export class IncomeController {
  constructor(private readonly s: IncomeService) {}
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
      bytes = await renderIncomeReport(d, format);
    res.setHeader(
      "Content-Type",
      format === "pdf"
        ? "application/pdf"
        : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    );
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="income-${d.from}-${d.until}.${format}"`,
    );
    res.setHeader("Cache-Control", "no-store");
    res.send(bytes);
  }
}
