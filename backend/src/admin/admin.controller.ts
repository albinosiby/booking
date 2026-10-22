import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import type { Actor } from "../common/auth.guard";
import { AdminGuard } from "./admin.guard";
import { AdminService } from "./admin.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/admin")
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly service: AdminService) {}
  @Get("me") me(@Req() r: AuthRequest) {
    return this.service.me(r.actor);
  }
  @Get("overview") overview(@Req() r: AuthRequest) {
    return this.service.overview(r.actor);
  }
  @Get("organizations") orgs(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.organizations(r.actor, q);
  }
  @Get("organizations/:id") org(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.organization(r.actor, id);
  }
  @Get("users") users(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.users(r.actor, q);
  }
  @Put("users/:id/active") active(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.setUserActive(r.actor, id, b);
  }
  @Get("support/tickets") tickets(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.tickets(r.actor, q);
  }
  @Get("support/tickets/:id") ticket(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.ticket(r.actor, id);
  }
  @Post("support/tickets/:id/reply") reply(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.reply(r.actor, id, b);
  }
  @Put("support/tickets/:id/status") ticketStatus(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.setTicketStatus(r.actor, id, b);
  }
  @Get("agent-requests") requests(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.agentRequests(r.actor, q);
  }
  @Put("agent-requests/:id") updateRequest(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.updateAgentRequest(r.actor, id, b);
  }
  @Get("audit") audit(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
  ) {
    return this.service.auditLog(r.actor, q);
  }
  @Get("agent-requests/:id/connection") connection(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.connection(r.actor, id);
  }
  @Put("agent-requests/:id/connection") saveConnection(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.saveConnection(r.actor, id, b);
  }
  @Post("agent-requests/:id/tool-key") toolKey(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.rotateToolKey(r.actor, id);
  }
}
