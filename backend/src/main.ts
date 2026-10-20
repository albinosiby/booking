import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { json } from "express";
import helmet from "helmet";
import { AppModule } from "./app.module";
async function bootstrap() {
  if (
    process.env.NODE_ENV === "production" &&
    ((process.env.AUTH_PROVIDER === "supabase"
      ? !process.env.SUPABASE_URL?.startsWith("https://") ||
        !process.env.SUPABASE_PUBLISHABLE_KEY?.startsWith("sb_publishable_")
      : process.env.FIREBASE_AUTH_EMULATOR_HOST ||
        !process.env.FIREBASE_PROJECT_ID ||
        process.env.FIREBASE_PROJECT_ID.startsWith("demo-")) ||
      !process.env.CORS_ORIGINS ||
      !process.env.PUBLIC_APP_URL?.startsWith("https://"))
  )
    throw new Error(
      "Production requires configured cloud authentication, explicit CORS and an HTTPS app URL.",
    );
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  app.use(helmet());
  app.use(json({ limit: "3mb" }));
  app.enableCors({
    origin: (
      process.env.CORS_ORIGINS || "http://localhost:8080,http://127.0.0.1:8080"
    ).split(","),
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
    allowedHeaders: ["Authorization", "Content-Type"],
  });
  app.enableShutdownHooks();
  await app.listen(
    Number(process.env.PORT || 3000),
    process.env.APP_BIND_HOST ||
      (process.env.NODE_ENV === "production" ? "0.0.0.0" : "127.0.0.1"),
  );
}
bootstrap().catch((e) => {
  console.error(e instanceof Error ? e.message : "Startup failed");
  process.exit(1);
});
