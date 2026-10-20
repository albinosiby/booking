import { MessagesService } from "./messages/messages.service";
import { MessagesController } from "./messages/messages.controller";
import { ExpensesService } from "./expenses/expenses.service";
import { ExpensesController } from "./expenses/expenses.controller";
import { AccountsService } from "./accounts/accounts.service";
import { AccountsController } from "./accounts/accounts.controller";
import { BookingService } from "./bookings/booking.service";
import { BookingController } from "./bookings/booking.controller";
import { HallService } from "./hall/hall.service";
import { HallController } from "./hall/hall.controller";
import { CourtService } from "./court/court.service";
import { CourtController } from "./court/court.controller";
import { PoolService } from "./pool/pool.service";
import { PoolController } from "./pool/pool.controller";
import { TurfService } from "./turf/turf.service";
import { TurfController } from "./turf/turf.controller";
import { Module } from "@nestjs/common";
import { APP_FILTER, APP_GUARD } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { HealthController } from "./common/health.controller";
import { Database } from "./common/database";
import { AuthGuard } from "./common/auth.guard";
import { ErrorsFilter } from "./common/errors.filter";
import { WorkspaceService } from "./workspace/workspace.service";
import {
  WorkspaceController,
  CatalogController,
} from "./workspace/workspace.controller";
@Module({
  imports: [ThrottlerModule.forRoot([{ ttl: 60000, limit: 120 }])],
  controllers: [
    MessagesController,
    ExpensesController,
    AccountsController,
    BookingController,
    WorkspaceController,
    CatalogController,
    HealthController,
    TurfController,
    HallController,
    CourtController,
    PoolController,
  ],
  providers: [
    MessagesService,
    ExpensesService,
    AccountsService,
    BookingService,
    Database,
    AuthGuard,
    WorkspaceService,
    TurfService,
    HallService,
    CourtService,
    PoolService,
    { provide: APP_FILTER, useClass: ErrorsFilter },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
