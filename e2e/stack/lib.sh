# Shared helpers for e2e/stack scripts; source this file.

STACK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT=ntppool-e2e

compose() {
    docker compose -p "$PROJECT" -f "$STACK_DIR/compose.yaml" "$@"
}

# Where up records the running stack: stack-id always, stripe when it was
# started with E2E_STRIPE. test and down follow it.
STATE_DIR=$STACK_DIR/.state

# compose for commands that use the running stack (down, test): compose.yaml
# requires the images, the id keys and STRIPE_MODE to parse, but only up uses
# their values.
compose_existing() {
    ACCOUNT_ID_KEY=unused VENDOR_ZONE_ID_KEY=unused STRIPE_MODE=${STRIPE_MODE:-stub} \
        API_IMAGE=${API_IMAGE:-harbor.ntppool.org/ntporg/api-e2e:sha-0000000} \
        STRIPE_GW_IMAGE=${STRIPE_GW_IMAGE:-harbor.ntppool.org/ntporg/stripe-gw:sha-0000000} \
        compose "$@"
}

# pinned_image <override> <pin file> <repository> [<release repository>]:
# print the override if set, else the pin file's image, after checking it is
# <repository>:sha-<hex> (a build) or <release repository>:<x.y.z> (a
# release). The release repository defaults to <repository>.
pinned_image() {
    local override=$1 pin=$2 repo=$3 relrepo=${4:-$3} image
    if [ -n "$override" ]; then
        image=$override
    else
        image=$(cat "$STACK_DIR/$pin")
    fi
    # trim leading and trailing whitespace
    image="${image#"${image%%[![:space:]]*}"}"
    image="${image%"${image##*[![:space:]]}"}"
    if ! [[ $image =~ ^harbor\.ntppool\.org/ntporg/($repo:sha-[0-9a-f]{7,}|$relrepo:[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        echo "invalid $repo image '$image': expected harbor.ntppool.org/ntporg/$repo:sha-<7 or more hex digits> or $relrepo:<x.y.z> (see $STACK_DIR/$pin)" >&2
        return 1
    fi
    printf '%s\n' "$image"
}

# Print the API image to use: $API_IMAGE if set, else the pin file.
api_image() {
    pinned_image "${API_IMAGE:-}" api-image api-e2e
}

# Print the stripe-gw image to use: $STRIPE_GW_IMAGE if set, else the pin file.
stripe_gw_image() {
    pinned_image "${STRIPE_GW_IMAGE:-}" stripe-gw-image stripe-gw
}

# stripe_secrets: export the e2e Stripe key, the billing portal
# configuration and the key's expiry date, each from the environment if set,
# else from the macOS keychain (service ntppool-e2e-stripe; e2e/stack/
# stripe-key stores them). Fails if one is missing or the key has expired.
stripe_secrets() {
    local pair var account value
    for pair in STRIPE_SECRET_KEY:secret_key \
        STRIPE_UPGRADE_PORTAL_CONFIGURATION:portal_configuration \
        STRIPE_KEY_EXPIRES:key_expires; do
        var=${pair%%:*}
        account=${pair#*:}
        if [ -z "${!var:-}" ]; then
            if ! command -v security >/dev/null 2>&1; then
                echo "$var is not set (and there is no macOS keychain to read it from)" >&2
                return 1
            fi
            if ! value=$(security find-generic-password -s ntppool-e2e-stripe -a "$account" -w 2>/dev/null); then
                echo "$var is not set and the keychain has no ntppool-e2e-stripe item '$account': run e2e/stack/stripe-key" >&2
                return 1
            fi
            printf -v "$var" '%s' "$value"
        fi
        export "${var?}"
    done
    "$STACK_DIR/stripe-expiry" "$STRIPE_KEY_EXPIRES"
}

# wait_healthy <service> <timeout-seconds>: poll the service's container
# health; on timeout, or if the container exits, print its logs and fail.
wait_healthy() {
    local service=$1 timeout=$2 deadline id status
    deadline=$((SECONDS + timeout))
    while :; do
        # -a: an exited container must reach the exited branch below.
        id=$(compose ps -a -q "$service")
        if [ -z "$id" ]; then
            echo "service $service has no container" >&2
            compose logs --no-color "$service" >&2 || true
            return 1
        fi
        status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")
        case $status in
        healthy) return 0 ;;
        exited | dead)
            echo "service $service is $status" >&2
            compose logs --no-color "$service" >&2 || true
            return 1
            ;;
        esac
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "service $service not healthy after ${timeout}s (status: $status)" >&2
            compose logs --no-color "$service" >&2 || true
            return 1
        fi
        sleep 1
    done
}
