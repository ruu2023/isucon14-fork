import type { Context } from "hono";
import type { RowDataPacket } from "mysql2";
import type { PoolConnection } from "mysql2/promise";
import type { Environment } from "./types/hono.js";
import type { Chair, Ride } from "./types/models.js";

// このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
export const matchOnce = async (dbConn: PoolConnection) => {
  // 待機時間が長いライドから最大10件取得する
  const [rides] = await dbConn.query<
    Array<Ride & RowDataPacket>
  >(
    "SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 20",
  );

  if (rides.length === 0) {
    return;
  }

  for (const ride of rides) {
    // アクティブかつ利用可能な椅子のうち、
    // ライドの乗車地点に最も近い椅子を1台取得する
    const [[matched]] = await dbConn.query<
      Array<Chair & { distance: number } & RowDataPacket>
    >(
      `
        SELECT
          c.*,
          ABS(cl.latitude - ?)
            + ABS(cl.longitude - ?) AS distance
        FROM chairs AS c
        INNER JOIN chair_locations AS cl
          ON cl.id = (
            SELECT cl2.id
            FROM chair_locations AS cl2
            WHERE cl2.chair_id = c.id
            ORDER BY cl2.created_at DESC
            LIMIT 1
          )
        WHERE c.is_active = TRUE
          AND NOT EXISTS (
            SELECT 1
            FROM rides AS assigned_ride
            WHERE assigned_ride.chair_id = c.id
              AND (
                NOT EXISTS (
                  SELECT 1
                  FROM ride_statuses AS completed_status
                  WHERE completed_status.ride_id = assigned_ride.id
                    AND completed_status.status = 'COMPLETED'
                )
                OR EXISTS (
                  SELECT 1
                  FROM ride_statuses AS unsent_status
                  WHERE unsent_status.ride_id = assigned_ride.id
                    AND unsent_status.chair_sent_at IS NULL
                )
              )
          )
        ORDER BY distance, c.id
        LIMIT 1
      `,
      [ride.pickup_latitude, ride.pickup_longitude],
    );

    // 利用可能な椅子がなければ、後続ライドにも割り当てられない
    if (!matched) {
      break;
    }

    await dbConn.query(
      "UPDATE rides SET chair_id = ? WHERE id = ?",
      [matched.id, ride.id],
    );
  }

  return;
};


export const internalGetMatching = async (
  ctx: Context<Environment>,
) => {
  await matchOnce(ctx.var.dbConn);
  return ctx.body(null, 204);
};
