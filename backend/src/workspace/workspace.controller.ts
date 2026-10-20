import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { Request, Response } from "express";
import { Country, State } from "country-state-city";
import { AuthGuard, Actor } from "../common/auth.guard";
import { acceptanceSchema } from "./validation";
import { WorkspaceService } from "./workspace.service";
type AuthRequest = Request & { actor: Actor };
@Controller("v1/catalog")
export class CatalogController {
  @Get() catalog() {
    return {
      countries: Country.getAllCountries().map((c) => ({
        code: c.isoCode,
        name: c.name,
      })),
      timezones: [
        ...new Set([
          "Asia/Kolkata",
          "UTC",
          ...Intl.supportedValuesOf("timeZone"),
        ]),
      ].sort(),
    };
  }
  @Get("states/:country") states(@Param("country") code: string) {
    return State.getStatesOfCountry(code).map((s) => ({
      code: s.isoCode,
      name: s.name,
    }));
  }
}
@Controller("v1")
@UseGuards(AuthGuard)
export class WorkspaceController {
  constructor(private readonly service: WorkspaceService) {}
  @Get("workspace") workspace(@Req() r: AuthRequest) {
    return this.service.workspace(r.actor);
  }
  @Get("organization/details") organizationDetails(@Req() r: AuthRequest) {
    return this.service.organizationDetails(r.actor);
  }
  @Patch("organization/details") updateOrganization(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.updateOrganization(r.actor, b);
  }
  @Post("organizations") organization(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.createOrganization(r.actor, b);
  }
  @Post("businesses") business(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.createBusiness(r.actor, b);
  }
  @Put("businesses/order") reorderBusinesses(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.reorderBusinesses(r.actor, b);
  }
  @Patch("businesses/:id") rename(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.renameBusiness(r.actor, id, b);
  }
  @Post("businesses/:id/resources") resource(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.addResource(r.actor, id, b);
  }
  @Delete("businesses/:id/resources/:resourceId") remove(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("resourceId", ParseUUIDPipe) resource: string,
  ) {
    return this.service.deleteResource(r.actor, id, resource);
  }
  @Patch("businesses/:id/configuration") configure(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.configure(r.actor, id, b);
  }
  @Post("businesses/:id/activate") activate(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.activate(r.actor, id);
  }
  @Get("team") team(@Req() r: AuthRequest) {
    return this.service.team(r.actor);
  }
  @Post("invitations") invite(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.invite(r.actor, b);
  }
  @Post("invitations/accept") accept(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.service.accept(r.actor, acceptanceSchema.parse(b).token);
  }
  @Delete("invitations/:id") cancel(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.revoke(r.actor, id, true);
  }
  @Delete("team/:id") revoke(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.service.revoke(r.actor, id, false);
  }
  @Patch("team/:id") update(
    @Req() r: AuthRequest,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() b: unknown,
  ) {
    return this.service.updateMember(r.actor, id, b);
  }
  @Post("organization/logo") uploadLogo(
    @Req() r: AuthRequest,
    @Body() b: { content_type?: string; base64?: string },
  ) {
    return this.service.uploadLogo(r.actor, b);
  }
  @Get("organization/logo") async logo(
    @Req() r: AuthRequest,
    @Res() res: Response,
  ) {
    const logo = await this.service.logo(r.actor);
    res
      .set({
        "Content-Type": logo.content_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      })
      .send(Buffer.from(logo.data));
  }
}
