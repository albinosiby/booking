import { Controller, Get } from "@nestjs/common";
import { Database } from "./database";
@Controller("health")
export class HealthController {
  constructor(private readonly database: Database) {}
  @Get() async check() {
    await this.database.query("SELECT 1");
    return { status: "ok" };
  }
}
