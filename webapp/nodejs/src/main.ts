import { serve } from "@hono/node-server";
import { Hono, type Context } from "hono";
import { createMiddleware } from "hono/factory";
import { pool } from "./db.js";
import { execSync } from "node:child_process";
import {
  appGetNearbyChairs,
  appGetNotification,
  appGetRides,
  appPostPaymentMethods,
  appPostRideEvaluatation,
  appPostRides,
  appPostRidesEstimatedFare,
  appPostUsers,
} from "./app_handlers.js";
import {
  chairGetNotification,
  chairPostActivity,
  chairPostChairs,
  chairPostCoordinate,
  chairPostRideStatus,
} from "./chair_handlers.js";
import { internalGetMatching } from "./internal_handlers.js";
import {
  appAuthMiddleware,
  chairAuthMiddleware,
  ownerAuthMiddleware,
} from "./middlewares.js";
import {
  ownerGetChairs,
  ownerGetSales,
  ownerPostOwners,
} from "./owner_handlers.js";
import type { Environment } from "./types/hono.js";

const app = new Hono<Environment>();
app.use(
  createMiddleware<Environment>(async (ctx, next) => {
    const connection = await pool.getConnection();
    ctx.set("dbConn", connection);
    try {
      await next();
    } finally {
      await connection.rollback();
      pool.releaseConnection(connection);
    }
  }),
);

app.post("/api/initialize", postInitialize);

// app handlers
app.post("/api/app/users", appPostUsers);

app.post("/api/app/payment-methods", appAuthMiddleware, appPostPaymentMethods);
app.get("/api/app/rides", appAuthMiddleware, appGetRides);
app.post("/api/app/rides", appAuthMiddleware, appPostRides);
app.post(
  "/api/app/rides/estimated-fare",
  appAuthMiddleware,
  appPostRidesEstimatedFare,
);
app.post(
  "/api/app/rides/:ride_id/evaluation",
  appAuthMiddleware,
  appPostRideEvaluatation,
);
app.get("/api/app/notification", appAuthMiddleware, appGetNotification);
app.get("/api/app/nearby-chairs", appAuthMiddleware, appGetNearbyChairs);

// owner handlers
app.post("/api/owner/owners", ownerPostOwners);

app.get("/api/owner/sales", ownerAuthMiddleware, ownerGetSales);
app.get("/api/owner/chairs", ownerAuthMiddleware, ownerGetChairs);

// chair handlers
app.post("/api/chair/chairs", chairPostChairs);

app.post("/api/chair/activity", chairAuthMiddleware, chairPostActivity);
app.post("/api/chair/coordinate", chairAuthMiddleware, chairPostCoordinate);
app.get("/api/chair/notification", chairAuthMiddleware, chairGetNotification);
app.post(
  "/api/chair/rides/:ride_id/status",
  chairAuthMiddleware,
  chairPostRideStatus,
);

// internal handlers
app.get("/api/internal/matching", internalGetMatching);

const port = 8080;
serve(
  {
    fetch: app.fetch,
    port,
    hostname: "0.0.0.0",
  },
  (addr) => {
    console.log(`Server is running on http://${addr.address}:${addr.port}`);
  },
);

async function postInitialize(ctx: Context<Environment>) {
  let paymentServer = "";
  try {
    const body = await ctx.req.json<{ payment_server?: string }>();
    if (body?.payment_server) {
      paymentServer = body.payment_server;
    }
  } catch {
    // Body is empty or non-JSON
  }

  try {
    execSync("../sql/init.sh", { stdio: "inherit" });
  } catch (error) {
    return ctx.text(`Failed to initialize\n${error}`, 500);
  }
  try {
    await ctx.var.dbConn.query(
      "UPDATE settings SET value = ? WHERE name = 'payment_gateway_url'",
      [paymentServer],
    );
  } catch (error) {
    return ctx.text(`Internal Server Error\n${error}`, 500);
  }
  return ctx.json({ language: "node" });
}
