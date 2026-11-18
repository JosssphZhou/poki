import { createInterface } from 'node:readline/promises';

export async function chooseProvider(wanted, configured) {
  if (wanted !== undefined) {
    if (wanted !== 'bluebubbles' && wanted !== 'photon') throw new Error('Choose --provider bluebubbles or --provider photon.');
    return wanted;
  }
  if (configured.length < 2) return configured[0] ?? 'bluebubbles';
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error('BlueBubbles and Photon are both configured for iMessage. Starting BlueBubbles; pass --provider photon to start Photon.');
    return 'bluebubbles';
  }
  const terminal = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = (await terminal.question('BlueBubbles and Photon are both configured for iMessage.\n  1. BlueBubbles\n  2. Photon\nChoose 1 or 2 [1]: ')).trim();
    if (answer === '' || answer === '1') return 'bluebubbles';
    if (answer === '2') return 'photon';
    throw new Error('Choose 1 for BlueBubbles or 2 for Photon.');
  } finally { terminal.close(); }
}
