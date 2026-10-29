import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import type { Request, Response } from "express";
import type { Actor } from "../common/auth.guard";
import { AdminMcpGuard } from "./admin-mcp.guard";
import { AdminMcpService } from "./admin-mcp.service";
type AuthRequest = Request & { actor: Actor };

@Controller("v1/admin-mcp/voice")
@UseGuards(AdminMcpGuard)
export class AdminMcpController {
  constructor(private readonly service: AdminMcpService) {}
  @Get("requests") list(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.list(r.actor, q);
  }
  @Get("requests/:org") get(@Req() r: AuthRequest, @Param("org") org: string) {
    return this.service.get(r.actor, org);
  }
  @Post("requests/:org/prepare") prepare(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.prepare(r.actor, org, b);
  }
  @Post("requests/:org/start") start(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.start(r.actor, org, b);
  }
  @Get("jobs/:org") job(@Req() r: AuthRequest, @Param("org") org: string) {
    return this.service.job(r.actor, org);
  }
  @Post("jobs/:org/claim") claim(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.claim(r.actor, org, b);
  }
  @Post("jobs/:org/checkpoint") checkpoint(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.checkpoint(r.actor, org, b);
  }
  @Post("jobs/:org/release") release(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.release(r.actor, org, b);
  }
  /** Private adapter transport only: never register this raw response as an MCP tool. */
  @Post("jobs/:org/credential") credential(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
    @Res({ passthrough: true }) res: Response,
  ) {
    res.setHeader("Cache-Control", "no-store");
    return this.service.credential(r.actor, org, b);
  }
  @Post("jobs/:org/verify") verify(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.verify(r.actor, org, b);
  }
  @Post("jobs/:org/activate") activate(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.activate(r.actor, org, b);
  }
  @Post("requests/:org/pause") pause(
    @Req() r: AuthRequest,
    @Param("org") org: string,
    @Body() b: unknown,
  ) {
    return this.service.pause(r.actor, org, b);
  }
}
