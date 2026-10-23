import process from "node:process";
import { Buffer } from "node:buffer";
import { EdgeDatabase } from "./database";
import { FcmSender } from "../src/notifications/fcm-sender";
import { NotificationDispatcher } from "../src/notifications/notification-dispatcher";
import { notificationHandler } from "./notifications-handler";
Object.assign(globalThis, { process, Buffer });
const db = new EdgeDatabase();
export const handler = notificationHandler(
  new NotificationDispatcher(db, new FcmSender()),
);
if (Deno.env.get("BOOKING_EDGE_TEST") !== "true") Deno.serve(handler);
