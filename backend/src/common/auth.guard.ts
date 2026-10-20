import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Database } from "./database";
import { supabaseActor } from "./supabase-auth";
export interface Actor {
  uid: string;
  email: string;
  name: string;
}
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly db: Database) {
    if (process.env.AUTH_PROVIDER !== "supabase" && !getApps().length)
      initializeApp({
        projectId: process.env.FIREBASE_PROJECT_ID || "demo-eden-booking",
        ...(!process.env.FIREBASE_AUTH_EMULATOR_HOST
          ? { credential: applicationDefault() }
          : {}),
      });
  }
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    const header = request.headers.authorization;
    if (typeof header !== "string" || !header.startsWith("Bearer "))
      throw new UnauthorizedException("Sign in to continue.");
    if (process.env.AUTH_PROVIDER === "supabase") {
      request.actor = await supabaseActor(header.slice(7), this.db);
      return true;
    }
    try {
      const token = await getAuth().verifyIdToken(header.slice(7), true);
      if (!token.email) throw new Error("Email required");
      if (process.env.NODE_ENV === "production" && !token.email_verified)
        throw new UnauthorizedException("Verify your email before continuing.");
      request.actor = {
        uid: token.uid,
        email: token.email.toLowerCase(),
        name: token.name || token.email.split("@")[0],
      } satisfies Actor;
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) throw error;
      throw new UnauthorizedException("Your session expired. Sign in again.");
    }
  }
}
