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
import { AdmissionService } from "./admission.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/admissions")
@UseGuards(AuthGuard)
export class AdmissionController {
  constructor(private readonly service: AdmissionService) {}
  @Get("customers") customers(@Req() r: AuthRequest, @Query("q") q = "") {
    return this.service.customers(r.actor, q);
  }
  @Get("catalog") catalog(@Req() r: AuthRequest) {
    return this.service.catalog(r.actor);
  }
  @Get("expired") expired(
    @Req() request: AuthRequest,
    @Query() query: unknown,
  ) {
    return this.service.expired(request.actor, query);
  }
  @Post(":id/delete") deleteMembership(
    @Req() request: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.service.deleteMembership(request.actor, id, body);
  }
  @Post("preview") preview(@Req() r: AuthRequest, @Body() v: unknown) {
    return this.service.preview(r.actor, v);
  }
  @Post("coach-conflicts") coachConflicts(
    @Req() r: AuthRequest,
    @Body() v: unknown,
  ) {
    return this.service.coachConflicts(r.actor, v);
  }
  @Get("classes") classes(@Req() r: AuthRequest, @Query() v: unknown) {
    return this.service.classes(r.actor, v);
  }
  @Get() list(@Req() r: AuthRequest, @Query() v: unknown) {
    return this.service.list(r.actor, v);
  }
  @Post() create(@Req() r: AuthRequest, @Body() v: unknown) {
    return this.service.create(r.actor, v);
  }
  @Get(":id") detail(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.detail(r.actor, id);
  }
  @Post(":id/check-ins") checkIn(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() v: unknown,
  ) {
    return this.service.checkIn(r.actor, id, v);
  }
  @Post(":id/sessions/:visitId/attendance") attendance(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("visitId", ParseUUIDPipe) visitId: string,
    @Body() v: unknown,
  ) {
    return this.service.attendance(r.actor, id, visitId, v);
  }
  @Post(":id/sessions/:visitId/change") sessionChange(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("visitId", ParseUUIDPipe) visitId: string,
    @Body() v: unknown,
  ) {
    return this.service.sessionChange(r.actor, id, visitId, v);
  }
  @Post(":id/payments") payments(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() v: unknown,
  ) {
    return this.service.payments(r.actor, id, v);
  }
  @Post(":id/cancel") cancel(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() v: unknown,
  ) {
    return this.service.cancel(r.actor, id, v);
  }
}
