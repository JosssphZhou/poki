import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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

test("Windows localizes stock Rust install progress and recovery without losing data", async () => {
  i18n.setLang("zh-Hans");
  for (const file of ["setup.rs", "device/pairing.rs", "device/devmode.rs", "device/ddi.rs", "device/install.rs"]) {
    const source = await readFile(new URL(`../../core/src/${file}`, import.meta.url), "utf8");
    const production = source.split("#[cfg(all(test,")[0];
    for (const [, title] of production.matchAll(/reporter\.step\("[^"]+", "([^"]+)"\)/g)) {
      assert.notEqual(i18n.progressLine(title), title, file + ": " + title);
    }
  }
  const cases = [
    ["More than one iPhone is plugged in. Choose one.", /请选择一部/],
    ["No iPhone found. Plug it in with a cable and unlock it.", /数据线连接并解锁/],
    ["The iPhone said Don't Trust. Unplug it, plug it in again and tap Trust.", /选择了“不信任”/],
    ["The iPhone no longer trusts this computer. Plug it in with a cable, unlock it and tap Trust, then try again.", /不再信任这台电脑/],
    ["The developer disk image is already mounted.", /开发者磁盘映像已挂载/],
    ["R2 download was interrupted. Using GitHub.", /下载中断，改用 GitHub/],
    ["The iPhone did not accept the app's signature. Make sure this iPhone is registered on the Apple ID's team and Developer Mode is on, then try again.", /未接受 App 签名/],
    ["The installed Poki has a different application signing identity. Keep Poki installed to preserve its data, and update it using the original signing identity on the original computer.", /请不要卸载 Poki.*原签名身份更新/],
    ["Signing Poki for Example Team", /正在为 Example Team 签名 Poki/],
    ["Poki 0.5.1 (456) signed for Example Team", /已为 Example Team 签名 Poki 0\.5\.1（456）/],
    ["Example Team (free, 7-day signing)", /Example Team（免费团队，签名有效期 7 天）/],
    ["App ID and profile for PokiWidgets", /为 PokiWidgets 设置 App ID 和描述文件/],
    ["Remote pairing did not finish (lockdown: InvalidHostID (0x42)). Poki can pair on the iPhone instead.", /远程配对未完成（lockdown: InvalidHostID \(0x42\)）/],
    ["The iPhone refused a provisioning profile: MobileInstallation (0xe8008001). On a free team the phone must be registered on the Apple ID; sign in again.", /iPhone 拒绝了描述文件：MobileInstallation \(0xe8008001\).*请重新登录/],
    ["The iPhone stopped answering while installing Poki (unlock the iPhone, check it for a prompt, then try again). Unplug it, plug it in again and unlock it, then try again.", /安装 Poki时，iPhone 停止响应/],
  ] as const;
  for (const [english, expected] of cases) assert.match(api.failureText({ kind: "device", message: english }), expected);
  const diagnostic = "third-party reply: %s [0x42]";
  assert.equal(i18n.progressLine(diagnostic), diagnostic);
  i18n.setLang("en");
  for (const [english] of cases) assert.equal(i18n.progressLine(english), english);
});
