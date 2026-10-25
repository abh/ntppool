-- Reference data for the e2e stack.
-- Rule: only data production also has. Per-test data goes through
-- `api e2e fixture`, never here. Runs after `api setup`, which has already
-- created the DNS root and the zones.
BEGIN;

INSERT INTO system_settings (key, value, created_on) VALUES
    ('environment', '"devel"', now()),
    ('features', '{"user-deletion": 1, "user-download": 1}', now()),
    ('validation', '{"server_v4": "https://validate4.ntppool.dev/d/", "server_v6": "https://validate6.ntppool.dev/d/"}', now()),
    ('monitor_server_verification_months', '18', now()),
    ('monitor_global_max', '0', now()),
    ('dns_settings', '{"ttl": 30}', now()),
    ('monitors', '{"interval_all": "30s", "interval_active": "5m", "interval_testing": "40m"}', now()),
    ('scorer', '{}', now()),
    ('vendors', '1', now())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Server for tests/scores.spec.ts (NTP_SCORES_TEST_IP, default 216.239.35.4).
-- The public /scores/<ip> page 404s for an unknown IP.
INSERT INTO accounts (id_token, name, public_profile, created_on)
VALUES ('2zrqgk7', 'Test Servers 1', false, now());

INSERT INTO servers (ip, ip_version, account_id, hostname, stratum, in_pool,
                     netspeed, netspeed_target, created_on, score_raw)
SELECT '216.239.35.4', 'v4', a.id, 'time.google.com', 1, 1,
       10000, 10000, now(), 20
FROM accounts a
WHERE a.id_token = '2zrqgk7';

INSERT INTO server_zones (server_id, zone_id)
SELECT s.id, z.id
FROM servers s
JOIN zones z ON z.name IN ('@', 'north-america', 'us')
WHERE s.ip = '216.239.35.4';

COMMIT;
