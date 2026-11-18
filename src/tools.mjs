import * as cua from './cua.mjs';
import { readFileSync } from 'node:fs';
import { McpServer } from '@modelcontextprotocol/server';
import { z } from 'zod';
import { version } from './build-info.mjs';

const catalog = JSON.parse(readFileSync(new URL('./data/tools.json', import.meta.url), 'utf8'));
export const defaultTools = cua.tools;
const mergedReplacements = {
  take_screenshot: 'look (returns the current screenshot and numbered elements; do also returns a screenshot after acting)',
  list_elements: 'look (or look with {"full": true} to list every element)',
  get_foreground_app: 'look (reports the foreground app on the first line)',
  observe_device: 'look (captures the element tree, OCR fallback, and screenshot together)',
  tap: 'do with {"actions": [{"tap": <element_number_or_[x,y]>}]}',
  tap_text: 'do with {"actions": [{"tap_text": "<text>"}]} (or call look first and use {"tap": <element_number>})',
  double_tap: 'do with {"actions": [{"double_tap": <element_number_or_[x,y]>}]}',
  long_press: 'do with {"actions": [{"long_press": <element_number_or_[x,y]>}]}',
  swipe: 'do with {"actions": [{"swipe": "up" | "down" | "left" | "right"}]} (or {"drag": [x1, y1, x2, y2]})',
  scroll: 'do with {"actions": [{"swipe": {"direction": "up" | "down" | "left" | "right", "in": <element_number>}}]}',
  scroll_to: 'do with {"actions": [{"scroll_to": "<text>"}]}',
  drag: 'do with {"actions": [{"drag": {"from": [x1, y1], "to": [x2, y2], "ms": 800, "hold_ms": 600}}]}',
  pinch: 'do with {"actions": [{"pinch": {"x": <x>, "y": <y>, "scale": <scale>}}]}',
  type_text: 'do with {"actions": [{"type": "<text>", "clear": false}]}',
  fill: 'do with {"actions": [{"type": "<text>", "ref": <element_number>, "clear": true}]}',
  press_key: 'do with {"actions": [{"key": "return" | "delete" | "tab" | "space" | "escape"}]}',
  press_button: 'do with {"actions": [{"button": "home" | "lock" | "volume_up" | "volume_down"}]}',
  go_back: 'do with {"actions": [{"back": true}]}',
  launch_app: 'do with {"actions": [{"launch": "<bundle_id>"}]} (call list_apps first if you need the bundle_id)',
  open_url: 'do with {"actions": [{"open_url": "<url>"}]}',
  handle_alert: 'look to read the alert buttons, then do with {"actions": [{"tap": <element_number>}]}',
  wait_for: 'do with {"actions": [{"wait_until": {"text": "<text>", "gone": false, "ms": 5000}}]}',
  wait: 'do with {"actions": [{"wait": <milliseconds>}]}',
  request_human_action: 'do with {"actions": [{"handoff": {"kind": "other", "text": "<reason>"}}]}',
  batch_commands: 'do with {"actions": [...]} (runs up to 20 actions in order and reads the screen once at the end)',
};
const devToolsInstructions = 'When the request already says what to do on the device, use do (or batch_commands in the developer catalog) for multi-step operations. With one device available, skip list_devices and select_device; use them when a call reports several devices. Consecutive calls do not require an explicit device lease.';
const readOnly = new Set(['observe_device','list_devices', 'get_device_info', 'take_screenshot', 'get_foreground_app', 'list_elements', 'list_apps', 'get_clipboard', 'list_crashes', 'get_crash', 'wait_for', 'wait']);
const guidance = {
  acquire_device: 'Only needed to keep other sessions off a device across several calls. One batch_commands call already runs without interruption, so a single-call task needs no lease. If you take one, keep the returned lease_id, renew before expiry, then release.',
  wait_for: 'The timeout covers device capture, AX, OCR and polling. Success includes the matching observation and its image, so a second screenshot is not needed to inspect the matched state.',
  batch_commands: `Batch known operations. A single visible input can be filled without field. Field and button labels come from observed screen text, in its original language; guesses such as a translated Search label or an unobserved New Tab button require an observation first.

Example:
{"commands":[
  {"tool":"launch_app","arguments":{"bundle_id":"com.example.app"}},
  {"tool":"fill","arguments":{"text":"hello","submit":true}},
  {"tool":"tap_text","arguments":{"text":"Open"}},
  {"tool":"go_back","arguments":{}},
  {"tool":"tap_text","arguments":{"text":"Show Alert"}},
  {"tool":"handle_alert","arguments":{"button":"OK"}}
]}

Arguments of common steps: launch_app {bundle_id or name}; tap_text {text}; tap {x, y}; fill {text, field (optional when one text field is visible), submit}; type_text {text}; press_key {key, modifiers, count}; scroll {direction}; scroll_to {text, direction}; swipe {from_x, from_y, to_x, to_y}; go_back {}; handle_alert {button or action}; wait_for {text, gone, timeout_seconds}; wait {seconds}; take_screenshot {}. Use tool names without any client prefix.`,
  fill: 'Omit field when only one text input is visible. When selecting among fields, copy the exact observed label or use a current ref; field labels are not translated. Prefer fill over separate tap + type_text when the target field is known: it uses the field already being edited or taps it once, confirms that exact field before clearing anything, and reads the text back from it before any Return. When the field cannot be confirmed, nothing is typed. Use submit=true only when sending is already authorized; otherwise inspect the draft first.',
  type_text: 'Requires an already focused field. When the target field is known, use fill instead to avoid focus mistakes. To send text already entered, use press_key key=return; do not call type_text with empty text. text_verified confirms input only, not delivery.',
  press_key: 'Use key=return to submit existing text after it has been checked; do not re-enter the text. A sent result only confirms key dispatch, so verify the app result before reporting delivery.',
  touch_path: 'For a circle, make one touch_path call that goes once around and runs about 10 degrees past its first point, so the ends meet even when an app ignores the first few points of movement. Measure the center and radius in points from a current screenshot and keep the whole shape inside the drawing area. Give about one point every 10 to 16 ms; a circle drawn over 1500 ms with 120 points looks smooth. Do not build a circle from several drags or a few corner points. Inspect a screenshot afterwards, and do not erase or redraw automatically.',
  draw_strokes: 'Plan every letter before the call: nothing generates lettering for you. Write cursive or block letters as curves sampled about every 10 to 16 ms, one stroke per pen lift, left to right, sized from a current screenshot of the canvas. Use it only on a canvas that does not scroll or pan when touched; when the canvas or tool must be checked between strokes, use separate touch_path calls. Inspect a screenshot afterwards.',
  launch_app: 'On a simulator it returns once the app shows readable elements, and on a physical device once the app is in front; either way its text is in screen, so there is no need to look again. resumed=true means the app was already running and kept its state; use fresh=true to start it anew. If launch fails with CoreDeviceError 4016, inspect the current screen and use the observed Home Screen or app switcher controls. Avoid repeating the same failing launch until device conditions change.',
};
// JSON Schema cannot say that time_ms increases, so the parsed arguments are checked before any device is touched.
const checkStroke = (points, ctx, path) => {
  if (points[0].time_ms !== 0) ctx.addIssue({ code: 'custom', path: [...path, 0, 'time_ms'], message: 'time_ms of the first point must be 0.' });
  const back = points.findIndex((point, index) => index > 0 && point.time_ms <= points[index - 1].time_ms);
  if (back > 0) ctx.addIssue({ code: 'custom', path: [...path, back, 'time_ms'], message: `time_ms must increase at every point; point ${back} has ${points[back].time_ms} after ${points[back - 1].time_ms}.` });
};
const strokeChecks = {
  touch_path: (args, ctx) => checkStroke(args.points, ctx, ['points']),
  draw_strokes: (args, ctx) => {
    args.strokes.forEach((stroke, index) => checkStroke(stroke.points, ctx, ['strokes', index, 'points']));
    const total = args.strokes.reduce((sum, stroke) => sum + stroke.points.at(-1).time_ms, 0);
    if (total > 60000) ctx.addIssue({ code: 'custom', path: ['strokes'], message: `The strokes together must last at most 60000 ms; these last ${total} ms.` });
  },
};
// Additive observation arguments: legacy clients retain their existing schema
// behavior and the upstream stroke timing refinements are preserved.
const actionObservationTools = new Set(['tap', 'double_tap', 'long_press', 'tap_text', 'swipe',
  'drag', 'scroll', 'pinch', 'type_text', 'fill', 'press_key', 'press_button', 'go_back', 'handle_alert']);
const schemaOf = tool => {
  const schemaWithObservations = actionObservationTools.has(tool.name)
    ? { ...tool.inputSchema, properties: { ...tool.inputSchema.properties,
      return_observation: { type: 'boolean', description: 'Request a ref-bearing post-input observation when available.' },
      post_action_ocr: { type: 'boolean', description: 'Capture after stable AX and check image OCR prompts (default false).' } } }
    : tool.name === 'observe_device'
      ? { ...tool.inputSchema, properties: { ...tool.inputSchema.properties,
        include_image: { type: 'boolean', description: 'Attach PNG (default true); false retains capture and prompt checks.' } } }
      : tool.inputSchema;
  const schema = z.fromJSONSchema(schemaWithObservations);
  return strokeChecks[tool.name] ? schema.superRefine(strokeChecks[tool.name]) : schema;
};
export const definitions = catalog.tools.map(tool => [tool.name, [tool.description, guidance[tool.name]].filter(Boolean).join('\n\n'), schemaOf(tool), readOnly.has(tool.name)]);
definitions.push(['disconnect_device', 'Close the selected remote device connection and its local helper. Cellular reconnection may require returning the iPhone to Wi-Fi. Does not undo input.', z.object({ device: z.string().optional() }), false]);
definitions.push(['reconnect_device', 'Re-establish the selected RemotePairing tunnel. Does not replay input. A new session may require Wi-Fi when iOS closes its remote pairing listener.', z.object({ device: z.string().optional() }), false]);
definitions.push(['poki_mcp_status', 'Report Poki MCP version, current Git commit, native bridge build time, tool count, connected-device count, selected device, approval mode for this session, and any available Poki update with release notes and the update command.', z.object({}), true]);

for (const [name, description, schema, readOnlyHint] of cua.definitions) definitions.push([name, description, z.fromJSONSchema(schema), readOnlyHint]);

export function isDevToolsEnabled({ env = process.env, argv = process.argv, inherited = false } = {}) {
  if (argv.includes('--dev-tools')) return true;
  const devEnv = env.POKI_MCP_DEV_TOOLS?.trim().toLowerCase();
  if (devEnv === '1' || devEnv === 'true') return true;
  if (devEnv === '0' || devEnv === 'false') return false;
  const legacy = env.POKI_MCP_TOOLS?.trim().toLowerCase();
  if (legacy === 'all' || legacy === 'dev') return true;
  if (legacy === 'default') return false;
  if (inherited) return true;
  return false;
}

export function disabledToolMessage(name) {
  const replacement = mergedReplacements[name];
  if (replacement) {
    return `Tool "${name}" has been merged into ${replacement}. Start Poki MCP with --dev-tools or set POKI_MCP_DEV_TOOLS=1 to call legacy tools directly.`;
  }
  return `Tool "${name}" is in the developer tool group and is disabled by default. Start Poki MCP with --dev-tools or set POKI_MCP_DEV_TOOLS=1 to enable developer tools.`;
}

const anyObjectSchema = z.object({}).passthrough();

export function createServer(call, { devTools = isDevToolsEnabled() } = {}) {
  const server = new McpServer({ name: 'poki-mcp', version }, { instructions: devTools ? devToolsInstructions : cua.instructions });
  for (const [name, description, inputSchema, readOnlyHint] of definitions) {
    const enabled = devTools || defaultTools.has(name);
    server.registerTool(name, { description, inputSchema: enabled ? inputSchema : anyObjectSchema, annotations: { readOnlyHint } }, async (args, extra) => {
      if (!enabled) return { isError: true, content: [{ type: 'text', text: disabledToolMessage(name) }] };
      try { return await call(name, args, { signal: extra.mcpReq?.signal ?? extra.signal, requestId: extra.mcpReq?._meta?.['poki/request_id'] }); }
      catch (error) { return { isError: true, content: [{ type: 'text', text: error.message }] }; }
    });
  }
  if (!devTools) {
    server.server.setRequestHandler('tools/list', () => ({
      tools: definitions.filter(([name]) => defaultTools.has(name)).map(([name, description, inputSchema, readOnlyHint]) => ({
        name, description, inputSchema: z.toJSONSchema(inputSchema, { io: 'input', target: 'draft-2020-12' }),
        annotations: { readOnlyHint },
      })),
    }));
  }
  return server;
}
