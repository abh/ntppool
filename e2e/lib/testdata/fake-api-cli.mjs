// Stands in for the api binary in lib/apicli.test.ts. The first argument
// picks the behavior; the request JSON arrives on stdin.
import { text } from "node:stream/consumers";

const mode = process.argv[2];
const input = await text(process.stdin);

switch (mode) {
  case "echo":
    process.stdout.write(
      JSON.stringify({ args: process.argv.slice(3), request: JSON.parse(input) }) + "\n",
    );
    break;
  case "fail":
    process.stderr.write("first line\nsecond line\nuser already exists\n");
    process.exit(3);
  case "malformed":
    process.stdout.write("not json\n");
    break;
  case "cwd":
    process.stdout.write(JSON.stringify({ cwd: process.cwd() }) + "\n");
    break;
  default:
    process.stderr.write(`unknown mode ${mode}\n`);
    process.exit(2);
}
