import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Put,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Actor, AuthGuard } from "../common/auth.guard";
import { WebsiteService } from "./website.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/booking-website")
@UseGuards(AuthGuard)
export class WebsiteSettingsController {
  constructor(private readonly service: WebsiteService) {}
  @Header("Cache-Control", "private, no-store")
  @Get("link")
  link(@Req() r: AuthRequest) {
    return this.service.link(r.actor);
  }
  @Get("home-hero")
  async homeHero(@Req() r: AuthRequest, @Res() res: Response) {
    const image = await this.service.homeHero(r.actor);
    res.set({
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    });
    if (!image) return res.status(204).end();
    return res.type(image.content_type).send(Buffer.from(image.data));
  }
  @Header("Cache-Control", "private, no-store")
  @Get()
  settings(@Req() r: AuthRequest) {
    return this.service.settings(r.actor);
  }
  @Header("Cache-Control", "private, no-store")
  @Put()
  save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(r.actor, b);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("publish")
  publish(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.publication(r.actor, "published", b);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("pause")
  pause(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.publication(r.actor, "paused", b);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("unpublish")
  unpublish(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.publication(r.actor, "unpublished", b);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("images")
  uploadImage(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.uploadImage(r.actor, b);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("images/:id/remove")
  removeImage(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Body() b: unknown,
  ) {
    return this.service.removeImage(r.actor, id, b);
  }
  @Get("images/:id")
  async image(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Res() res: Response,
  ) {
    const image = await this.service.ownerImage(r.actor, id);
    res
      .set({
        "Content-Type": image.content_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      })
      .send(Buffer.from(image.data));
  }
  @Header("Cache-Control", "private, no-store")
  @Post("preview")
  preview(@Req() r: AuthRequest) {
    return this.service.preview(r.actor);
  }
}
@Controller("public/v1/sites/:slug")
export class PublicWebsiteController {
  constructor(private readonly service: WebsiteService) {}
  @Get("payment-qr")
  async paymentQr(
    @Param("slug") slug: string,
    @Query("preview") preview: string | undefined,
    @Query("v") version: string | undefined,
    @Res() res: Response,
  ) {
    const image = await this.service.paymentQr(slug, preview, version);
    res
      .set({
        "Content-Type": image.content_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      })
      .send(Buffer.from(image.data));
  }
  @Header("Cache-Control", "private, no-store")
  @Get()
  catalog(@Param("slug") slug: string, @Query("preview") preview?: string) {
    return this.service.catalog(slug, preview);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("catalog")
  catalogAlias(
    @Param("slug") slug: string,
    @Query("preview") preview?: string,
  ) {
    return this.service.catalog(slug, preview);
  }
  @Header("Cache-Control", "private, no-store")
  @Get("logo")
  async logo(
    @Param("slug") slug: string,
    @Query("preview") preview: string | undefined,
    @Res() res: Response,
  ) {
    const result = await this.service.logo(slug, preview);
    res
      .set({
        "Content-Type": result.content_type,
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      })
      .send(Buffer.from(result.data));
  }
  @Get("images/:id")
  async image(
    @Param("slug") slug: string,
    @Param("id") id: string,
    @Query("preview") preview: string | undefined,
    @Res() res: Response,
  ) {
    const image = await this.service.image(slug, id, preview);
    res
      .set({
        "Content-Type": image.content_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      })
      .send(Buffer.from(image.data));
  }
  @Header("Cache-Control", "private, no-store")
  @Post("availability")
  availability(
    @Param("slug") slug: string,
    @Body() b: unknown,
    @Query("preview") preview?: string,
  ) {
    return this.service.availability(slug, b, preview);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("quote")
  quote(
    @Param("slug") slug: string,
    @Body() b: unknown,
    @Query("preview") preview?: string,
  ) {
    return this.service.quote(slug, b, preview);
  }
  @Header("Cache-Control", "private, no-store")
  @Post("bookings")
  book(
    @Param("slug") slug: string,
    @Body() b: unknown,
    @Query("preview") preview?: string,
  ) {
    return this.service.book(slug, b, preview);
  }
}
