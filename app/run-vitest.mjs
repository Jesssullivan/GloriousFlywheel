import { startVitest } from "vitest/node";

const vitest = await startVitest("test", [], { reporter: ["verbose"] });
if (!vitest) process.exit(1);
await vitest.close();
const failed = vitest.state.getCountOfFailedTests();
process.exit(failed > 0 ? 1 : 0);
