/**
 * Type definitions for NTP Pool API responses
 */

export interface ServerHistoryPoint {
  /** Unix timestamp */
  ts: number;
  /** Parsed Date object (added by client) */
  date: Date;
  /** Time offset in seconds */
  offset: number;
  /** Score step value */
  step: number;
  /** Server score */
  score: number;
  /** Monitor ID or null for aggregated data */
  monitor_id: number | null;
  /** Round trip time in milliseconds */
  rtt?: number;
}

export interface ZoneHistoryPoint {
  /** Date in YYYY-MM-DD format */
  d: string;
  /** Unix timestamp */
  ts: number;
  /** Parsed Date object (added by client) */
  date: Date;
  /** Registered server count */
  rc: number;
  /** Active server count */
  ac: number;
  /** Network capacity (netspeed active) */
  w: number;
  /** IP version */
  iv: 'v4' | 'v6';
}

export interface Monitor {
  /** Monitor unique identifier */
  id: number;
  /** Monitor display name */
  name: string;
  /** Monitor type */
  type: string;
  /** Timestamp (ISO string) */
  ts: string;
  /** Current score */
  score: number;
  /** Monitor status */
  status: 'active' | 'testing' | 'candidate' | 'pending' | 'paused' | 'deleted';
  /** Average round trip time */
  avg_rtt?: number;
}

export interface Server {
  /** Server IP address */
  ip: string;
  /** Server hostname (optional) */
  hostname?: string;
}

/**
 * Response from /api/server/scores/{server}/json
 */
export interface ServerScoreHistoryResponse {
  /** Server information */
  server: Server;
  /** Historical data points */
  history: Omit<ServerHistoryPoint, 'date'>[];
  /** Available monitors */
  monitors: Monitor[];
}

/**
 * Response from /api/zone/counts/{zone_name}
 */
export interface ZoneCountsResponse {
  /** Historical data points */
  history: Omit<ZoneHistoryPoint, 'date'>[];
}

export interface ApiError {
  /** Error message */
  error: string;
  /** Optional trace ID for debugging */
  trace_id?: string;
}

export interface FetchResult<T> {
  /** Whether the request was successful */
  success: boolean;
  /** Response data (present when success is true) */
  data?: T;
  /** Error message (present when success is false) */
  error?: string;
}
