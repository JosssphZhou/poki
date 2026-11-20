import { createInterface } from 'node:readline/promises';

const question = `BlueBubbles and Photon are both configured for iMessage.

1. BlueBubbles (default)
   Your own Messages account, through BlueBubbles Server on your Mac.

2. Photon
   The number Photon assigned to your sender. Task text and replies pass
   through Photon's servers.

Choose 1 or 2 [1]: `;

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
    const answer = (await terminal.question(question)).trim();
    if (answer === '' || answer === '1') return 'bluebubbles';
    if (answer === '2') return 'photon';
    throw new Error('Choose 1 for BlueBubbles or 2 for Photon.');
  } finally { terminal.close(); }
}
