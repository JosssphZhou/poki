export type Step = { id: string; title: string; state: "todo" | "active" | "done" | "failed" | "waiting"; detail?: string; fraction?: number; notes: string[] };

export function failStep(steps: Step[], text: string): Step[] {
  let index = steps.length - 1;
  while (index >= 0 && steps[index].state !== "active" && steps[index].state !== "waiting") index--;
  if (index < 0) {
    return [...steps, { id: "failure", title: "Could not finish", state: "failed", detail: text, notes: [] }];
  }
  return steps.map((s, i) => i === index ? { ...s, state: "failed", detail: text } : s);
}
