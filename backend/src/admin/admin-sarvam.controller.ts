import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor } from "../common/auth.guard";
import { AdminGuard } from "./admin.guard";
import { AdminSarvamService } from "./admin-sarvam.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/admin/sarvam")
@UseGuards(AdminGuard)
export class AdminSarvamController {
  constructor(private service: AdminSarvamService) {}
  @Get() status(@Req() r: AuthRequest) {
    return this.service.status(r.actor);
  }
  @Put() save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(r.actor, b);
  }
  @Post("connect") connect(@Req() r: AuthRequest) {
    return this.service.connect(r.actor);
  }
  @Post("callback") callback(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.callback(r.actor, b);
  }
  @Get("inventory") inventory(@Req() r: AuthRequest) {
    return this.service.inventory(r.actor);
  }
  @Get("jobs/:id") job(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.job(r.actor, id);
  }
  @Post("jobs/:id/approve") approve(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.approve(r.actor, id, b);
  }
  @Post("jobs/:id/resume") resume(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.resume(r.actor, id);
  }
}
