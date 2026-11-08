// The OpenAI Realtime session Poki's voice opens: the instructions, the voice tools and the request for
// a one-minute client secret. The voice bridge (bin/voice-bridge.mjs) sends this request with the key on
// the Mac. The Poki app sends the default one itself with the OpenAI key saved on the phone; it bundles
// it as native/ios-app/Poki/Voice/RealtimeSecretRequest.json, written by `node src/voice-session.mjs`.
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { root } from './config.mjs';

export const defaultModel = 'gpt-realtime-2.1';
export const phoneRequestFile = join(root, 'native/ios-app/Poki/Voice/RealtimeSecretRequest.json');

const instructions = macTools => `You are Poki, a voice assistant that operates the user's iPhone with tools.
Speak briefly: one short sentence per reply, in the user's language.
When a tool can answer or do what the user asks, call it at once, without speaking first. Never guess facts about the phone; use a tool.
A request can take several steps (open an app, tap, type): call one tool after another until it is done, then say in one short sentence that it is done. Never repeat an action that already ran, including actions from before a reconnect that the conversation says have finished.
Tapping something that sends, pays, deletes or calls waits until the user allows it on the phone; if the result says they did not, tell them in one sentence and do not try another way.
Only the user approves, with their own finger: never open Poki to tap Allow, Deny or anything else in it.
If the user tells you to stop or be quiet, stop talking, but anything already running keeps running; when its result arrives, report it in one sentence.
To read a page, open it first, then read the screen.${macTools ? '' : `
With do, open an app by its bundle id (Notes com.apple.mobilenotes, Weather com.apple.weather, Settings com.apple.Preferences, Messages com.apple.MobileSMS, Calculator com.apple.calculator, Clock com.apple.mobiletimer) and put several actions in one do when you know them; tap elements by the numbers from the latest look or do.`}`;

// The voice tools. `local` tools are answered by the phone itself; the bridge runs the others through Poki MCP.
export const phoneTools = [
  { name: 'get_ios_version', local: true, description: 'Read the iPhone model and its iOS version. Changes nothing on the phone.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'look', local: true, description: 'Read the iPhone screen now: the app in front and its numbered elements (role, label, frame in points).', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'do', local: true, description: 'Run actions on the iPhone in order, then read the screen once. Actions: {launch: "bundle id"}; {tap: n} or {tap: [x, y]}; {type: "text", ref?: n} (taps n first, then types); {key: "return"}; {scroll_to: "text"}; {swipe: "up"|"down"|"left"|"right"}; {button: "home"}; {wait_until: "text"}; {wait: ms}. The answer says what each action did and what is new on screen.', parameters: { type: 'object', properties: { actions: { type: 'array', items: { type: 'object' } } }, required: ['actions'], additionalProperties: false } },
];
export const macVoiceTools = [
  { name: 'get_ios_version', local: true, description: 'Read the iPhone model and its iOS version. Changes nothing on the phone.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_settings', description: 'Open the Settings app on the iPhone, or one of its pages (about, general, software_update, battery, wifi, display, and so on). Leave out page to open Settings itself.', parameters: { type: 'object', properties: { page: { type: 'string', enum: ['about', 'general', 'software_update', 'battery', 'wifi', 'bluetooth', 'display', 'sounds', 'notifications', 'privacy', 'screen_time'] } }, additionalProperties: false } },
  { name: 'read_screen', description: 'Read the text and controls on the iPhone screen now.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_app', description: 'Open an app on the iPhone by its name, for example Calculator, Clock, Weather.', parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'], additionalProperties: false } },
  { name: 'tap_text', description: 'Tap the visible button or row whose text matches.', parameters: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } },
  { name: 'go_home', description: 'Go to the Home Screen.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
];

export const voiceTools = macTools => macTools ? macVoiceTools : phoneTools;

export function sessionConfig({ macTools = false, model = defaultModel, effort = 'low', vad = 'server_vad', voice = 'marin' } = {}) {
  const turn = vad === 'semantic_vad'
    ? { type: 'semantic_vad', eagerness: 'high', create_response: true, interrupt_response: true }
    : { type: 'server_vad', silence_duration_ms: 450, prefix_padding_ms: 300, threshold: 0.5, create_response: true, interrupt_response: true };
  return {
    type: 'realtime',
    model,
    instructions: instructions(macTools),
    output_modalities: ['audio'],
    audio: {
      input: { turn_detection: turn, noise_reduction: { type: 'near_field' }, transcription: { model: 'gpt-4o-mini-transcribe' } },
      output: { voice },
    },
    tools: voiceTools(macTools).map(({ name, description, parameters }) => ({ type: 'function', name, description, parameters })),
    tool_choice: 'auto',
    parallel_tool_calls: false,
    reasoning: { effort },
  };
}

// The body of POST https://api.openai.com/v1/realtime/client_secrets.
export const clientSecretRequest = session => ({ expires_after: { anchor: 'created_at', seconds: 60 }, session });

// What the phone sends with its own key: the bridge's default session (the phone runs every tool in it).
export const phoneRequest = () => clientSecretRequest(sessionConfig());

if (import.meta.main) await writeFile(phoneRequestFile, JSON.stringify(phoneRequest(), null, 2) + '\n');
