import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { after, before, test } from "node:test";
import { createServer } from "vite";

let server, api, i18n;
const globals = {
  localStorage: { getItem: () => "en", setItem: () => {} },
  document: { documentElement: { dataset: {} } },
  window: {},
};
const saved = Object.getOwnPropertyDescriptors(globalThis);

before(async () => {
  for (const [key, value] of Object.entries(globals)) {
    Object.defineProperty(globalThis, key, { configurable: true, value });
  }
  server = await createServer({
    configFile: false,
    root: fileURLToPath(new URL("..", import.meta.url)),
    server: { middlewareMode: true, ws: false, watch: null },
    optimizeDeps: { noDiscovery: true },
  });
  api = await server.ssrLoadModule("/src/api.ts");
  i18n = await server.ssrLoadModule("/src/i18n.ts");
});

after(async () => {
  await server?.close();
  for (const key of Object.keys(globals)) {
    if (saved[key]) Object.defineProperty(globalThis, key, saved[key]);
    else Reflect.deleteProperty(globalThis, key);
  }
});

test("Windows resets the install progress before an approved retry, not a decline", async () => {
  for (const approved of [false, true]) {
    const history = [];
    let visibleSteps = ["checking the running app"];
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, args) => {
        if (cmd === "dev_state") return { prefs: { close_without_asking: false } };
        if (cmd === "plugin:dialog|message") {
          history.push("asked");
          return args.buttons.OkCancelCustom[approved ? 0 : 1];
        }
        assert.equal(cmd, "install");
        history.push(args.closePoki);
        if (!args.closePoki) throw { kind: "poki_running" };
        assert.deepEqual(visibleSteps, [], "old progress must be gone before the second install starts");
        return { record: { version: "example" } };
      },
    };
    const pending = api.installClosingPoki("fixture", "Example iPhone", false, null, null, () => {
      history.push("reset");
      visibleSteps = [];
    });
    if (approved) {
      assert.equal((await pending).record.version, "example");
      assert.deepEqual(history, [false, "asked", "reset", true]);
    } else {
      await assert.rejects(pending, { kind: "cancelled" });
      assert.deepEqual(history, [false, "asked"]);
    }
  }
});

test("Windows certificate warning keeps the identity and consequence in both languages", () => {
  const certificate = {
    name: "Example Certificate {days}", serial: "5F00", machine: "Example Mac", days_left: 3,
  };
  const error = { kind: "certificate_limit", message: "English fallback", certificate };
  const english = api.failureText(error);
  assert.match(english, /Every app signed with the old certificate will stop opening/);
  assert.match(english, /Example Certificate \{days\}.*5F00.*Example Mac/);
  assert.match(english, /It expires in 3 days/);

  i18n.setLang("zh-Hans");
  const chinese = api.failureText(error);
  assert.match(chinese, /使用旧证书签名的 App 都将无法打开，直到使用有效证书重新安装/);
  assert.match(chinese, /Example Certificate \{days\}.*5F00.*Example Mac/);
  assert.match(chinese, /3 天后到期/);
  assert.equal(api.failureText({ kind: "certificate_limit", message: "English fallback" }), "English fallback");
});
