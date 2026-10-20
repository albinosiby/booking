import {
  Body,
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Param,
  Req,
  UseGuards,
} from "@nestjs/common";
import { Request } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { MessagesService } from "./messages.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/message-templates")
@UseGuards(AuthGuard)
export class MessagesController {
  constructor(private readonly service: MessagesService) {}
  @Get() catalog(@Req() r: AuthRequest) {
    return this.service.catalog(r.actor);
  }
  @Post() create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.create(r.actor, b);
  }
  @Put("primary") primary(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.primary(r.actor, b);
  }
  @Delete(":id") remove(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.remove(r.actor, id);
  }
}
