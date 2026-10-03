# Shared helpers for e2e/stack scripts; source this file.

STACK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT=ntppool-e2e

compose() {
    docker compose -p "$PROJECT" -f "$STACK_DIR/compose.yaml" "$@"
}

# compose for commands that use the running stack (down, test): compose.yaml
# requires API_IMAGE and the id keys to parse, but only up uses their values.
compose_existing() {
    ACCOUNT_ID_KEY=unused VENDOR_ZONE_ID_KEY=unused \
        API_IMAGE=${API_IMAGE:-harbor.ntppool.org/ntporg/api-dev:sha-0000000} \
        compose "$@"
}

# Print the API image to use: $API_IMAGE if set, else the pin file.
api_image() {
    local image
    if [ -n "${API_IMAGE:-}" ]; then
        image=$API_IMAGE
    else
        image=$(cat "$STACK_DIR/api-image")
    fi
    # trim leading and trailing whitespace
    image="${image#"${image%%[![:space:]]*}"}"
    image="${image%"${image##*[![:space:]]}"}"
    if ! [[ $image =~ ^harbor\.ntppool\.org/ntporg/api-dev:sha-[0-9a-f]{7,}$ ]]; then
        echo "invalid API image '$image': expected harbor.ntppool.org/ntporg/api-dev:sha-<7 or more hex digits> (see $STACK_DIR/api-image)" >&2
        return 1
    fi
    printf '%s\n' "$image"
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
