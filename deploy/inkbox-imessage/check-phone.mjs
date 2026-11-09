import { connectPoki } from './poki.mjs';

try {
  if (!process.env.POKI_MCP_URL) throw new Error('请先在本机私密环境中设置 POKI_MCP_URL。');
  const client = await connectPoki(process.env.POKI_MCP_URL);
  try {
    const listing = await client.list();
    const available = listing.tools?.some(tool => tool.name === 'ask_poki');
    console.log(available ? 'Poki 已连接，ask_poki 可用。' : 'Poki 已连接，但未公布 ask_poki。');
    if (!available) process.exitCode = 2;
  } finally {
    await client.close();
  }
} catch (error) {
  console.error(error instanceof TypeError ? '请核对 Poki Relay 的 Connector URL。' : error.message);
  process.exitCode = 1;
}
